import Foundation
import SwiftSoup

/// Đánh giá rule nguồn Legado trên một nội dung (spec §2).
///
/// Một analyzer = một trang/nội dung gốc (`content`, URL nền `baseUrl`, thân thô `src`). Rule trường của từng mục
/// danh sách đánh giá bằng tham số `in:`; khi đó mục là nội dung hiện hành nhưng `baseUrl`/`src` vẫn là của trang.
///
/// Chỉ gọi trên thread engine (bên trong `LegadoEngineSession.run`). Mọi hàm chỉ ném `CancellationError`: lỗi rule
/// (regex/CSS/JS hỏng) cho kết quả rỗng và được ghi vào `session.diagnostics` (spec §6.1).
final class LegadoRuleAnalyzer {
    enum Kind {
        case elements
        case stringList
        case string
    }

    let session: LegadoEngineSession
    let content: LegadoContentNode
    let baseUrl: String
    let src: String?
    /// Thay placeholder trong mã JS của rule **trước** khi chạy (§2.7). Đúng cho rule trường; URL/exploreUrl không đi qua đây.
    var substitutesPlaceholdersInJS = true

    var xpathRootDocument: LegadoXPathDocument?

    init(session: LegadoEngineSession, content: LegadoContentNode, baseUrl: String, src: String?) {
        self.session = session
        self.content = content
        self.baseUrl = baseUrl
        self.src = src
    }

    // MARK: - API cho luồng

    /// `getElements` (§2.1): rule danh sách (`bookList`, `chapterList`, `init`). Hỗ trợ tiền tố `-` (đảo) / `+`.
    func elements(_ rule: String, in item: LegadoContentNode? = nil) throws -> [LegadoContentNode] {
        try evaluate(rule, kind: .elements, content: item ?? content, isRoot: item == nil).finalElements
    }

    /// Phần tử/giá trị đầu của `getElements`, hoặc `nil`.
    func element(_ rule: String, in item: LegadoContentNode? = nil) throws -> LegadoContentNode? {
        try elements(rule, in: item).first
    }

    /// `getString`: một chuỗi (nhiều giá trị nối `\n`).
    func string(_ rule: String, in item: LegadoContentNode? = nil) throws -> String {
        try evaluate(rule, kind: .string, content: item ?? content, isRoot: item == nil).finalString
    }

    /// `getStringList`: danh sách chuỗi không rỗng (`nextTocUrl`, `nextContentUrl`).
    func strings(_ rule: String, in item: LegadoContentNode? = nil) throws -> [String] {
        try evaluate(rule, kind: .stringList, content: item ?? content, isRoot: item == nil).finalStrings
    }

    /// Trường URL (§2.15): `getString` rồi tuyệt đối hoá theo `baseUrl` (khối option `,{…}` giữ nguyên).
    /// `javascript:…`, `#`, rỗng ⇒ `""`.
    func url(_ rule: String, in item: LegadoContentNode? = nil) throws -> String {
        let raw = try string(rule, in: item)
        return LegadoURLResolver.absoluteFieldURL(raw, base: baseUrl, fallbackBase: session.source.baseURL)
    }

    /// Như `url` nhưng cho `getStringList` (trang kế của mục lục/nội dung).
    func urls(_ rule: String, in item: LegadoContentNode? = nil) throws -> [String] {
        try strings(rule, in: item)
            .map { LegadoURLResolver.absoluteFieldURL($0, base: baseUrl, fallbackBase: session.source.baseURL) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Đường ống (§2.2)

    /// Đánh giá đầy đủ một chuỗi rule theo dạng yêu cầu. Kết quả: `.string` cho `.string`, `.list` cho hai dạng còn lại.
    ///
    /// `isRoot`: nội dung là nội dung gốc của trang (không phải một mục). Khi đó phân đoạn JS **đứng đầu** nhận `result`
    /// là **chuỗi thân trang** (`src`), đúng cách nguồn dùng (`JSON.parse(result)`, `result.match(…)`,
    /// `Jsoup.parse(result)` — quan sát corpus); trên một mục, `result` là chính mục (object JSON / phần tử).
    func evaluate(_ rule: String, kind: Kind, content start: LegadoContentNode, isRoot: Bool = false) throws -> LegadoContentNode {
        try session.checkCancellation()
        var text = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return kind == .string ? .string("") : .list([]) }
        var reverse = false
        if kind == .elements {
            if text.hasPrefix("-") {
                reverse = true
                text.removeFirst()
            } else if text.hasPrefix("+") {
                text.removeFirst()
            }
        }

        var current = start
        var currentIsPage = isRoot
        for segment in LegadoRuleScanner.segments(text) {
            try session.checkCancellation()
            switch segment {
            case .rule(let ruleText):
                current = try evaluateExpression(ruleText, kind: kind, content: current)
            case .js(let code):
                var script = code
                if substitutesPlaceholdersInJS, LegadoRuleScanner.containsScriptPlaceholder(code) {
                    script = try renderTemplate(code, content: current, mode: .raw, isScript: true).text
                }
                let input: LegadoContentNode
                if currentIsPage, let src {
                    input = .string(src)
                } else {
                    input = current
                }
                current = try session.evaluateScript(script, result: input, baseUrl: baseUrl, src: src, frameContent: current)
            }
            currentIsPage = false
        }

        switch kind {
        case .string:
            return .string(current.finalString)
        case .stringList:
            return .list(current.finalStrings.map { LegadoContentNode.string($0) })
        case .elements:
            let items = current.finalElements
            return .list(reverse ? Array(items.reversed()) : items)
        }
    }

    // MARK: - Biểu thức (§2.5)

    struct LeafResult {
        var value: LegadoContentNode
        var hadEmptyPlaceholder: Bool

        var isEmptyForAlternative: Bool {
            hadEmptyPlaceholder || value.isEmptyResult
        }
    }

    func evaluateExpression(_ text: String, kind: Kind, content: LegadoContentNode) throws -> LegadoContentNode {
        if kind == .elements, text.hasPrefix(":") {
            return .list(regexList(String(text.dropFirst()), content: content))
        }
        let alternatives = LegadoRuleScanner.split(text, by: "||").filter { !$0.isEmpty }
        // Không có `||`: placeholder rỗng chỉ để lại phần chữ xung quanh (`第{{$.n}}章##第章`, §2.7).
        if alternatives.count <= 1 {
            return try evaluateConjunction(alternatives.first ?? text, kind: kind, content: content).value
        }
        var last = LeafResult(value: emptyValue(kind), hadEmptyPlaceholder: false)
        for alternative in alternatives {
            let result = try evaluateConjunction(alternative, kind: kind, content: content)
            if !result.isEmptyForAlternative { return result.value }
            last = result
        }
        // Mọi vế đều "thất bại": vế mẫu có placeholder rỗng không được dùng làm kết quả (U6).
        return last.hadEmptyPlaceholder ? emptyValue(kind) : last.value
    }

    private func evaluateConjunction(_ text: String, kind: Kind, content: LegadoContentNode) throws -> LeafResult {
        let parts = LegadoRuleScanner.split(text, by: "&&").filter { !$0.isEmpty }
        if parts.count <= 1 {
            return try evaluateInterleave(parts.first ?? text, kind: kind, content: content)
        }
        var results: [LeafResult] = []
        for part in parts {
            let result = try evaluateInterleave(part, kind: kind, content: content)
            results.append(result)
        }
        let anyEmptyPlaceholder = results.contains { $0.hadEmptyPlaceholder }
        switch kind {
        case .string:
            let joined = results.map { $0.value.finalString }.filter { !$0.isEmpty }.joined(separator: "\n")
            return LeafResult(value: .string(joined), hadEmptyPlaceholder: anyEmptyPlaceholder)
        case .stringList, .elements:
            let items = results.flatMap { listItems($0.value) }
            return LeafResult(value: .list(items), hadEmptyPlaceholder: anyEmptyPlaceholder)
        }
    }

    /// `%%`: xen kẽ A₀, B₀, A₁, B₁… (vế ngắn hết thì bỏ qua) — U-điểm, xem spec §2.5.
    private func evaluateInterleave(_ text: String, kind: Kind, content: LegadoContentNode) throws -> LeafResult {
        let parts = LegadoRuleScanner.split(text, by: "%%").filter { !$0.isEmpty }
        if parts.count <= 1 {
            return try evaluateLeaf(parts.first ?? text, kind: kind, content: content)
        }
        var columns: [[LegadoContentNode]] = []
        var anyEmptyPlaceholder = false
        for part in parts {
            let result = try evaluateLeaf(part, kind: kind, content: content)
            anyEmptyPlaceholder = anyEmptyPlaceholder || result.hadEmptyPlaceholder
            if kind == .string {
                let lines = result.value.finalString.components(separatedBy: "\n").filter { !$0.isEmpty }
                columns.append(lines.map { LegadoContentNode.string($0) })
            } else {
                columns.append(listItems(result.value))
            }
        }
        var merged: [LegadoContentNode] = []
        let longest = columns.map { $0.count }.max() ?? 0
        for row in 0..<longest {
            for column in columns where row < column.count {
                merged.append(column[row])
            }
        }
        if kind == .string {
            return LeafResult(value: .string(merged.map { $0.finalString }.joined(separator: "\n")),
                              hadEmptyPlaceholder: anyEmptyPlaceholder)
        }
        return LeafResult(value: .list(merged), hadEmptyPlaceholder: anyEmptyPlaceholder)
    }

    func emptyValue(_ kind: Kind) -> LegadoContentNode {
        kind == .string ? .string("") : .list([])
    }

    func listItems(_ value: LegadoContentNode) -> [LegadoContentNode] {
        if case .list(let items) = value { return items }
        if case .string(let text) = value { return text.isEmpty ? [] : [value] }
        if case .null = value { return [] }
        return [value]
    }

    // MARK: - Biến (§2.10)

    /// Chạy một `@put:{k:rule,…}` trên nội dung hiện hành; mỗi giá trị là rule `getString`.
    func runPut(_ objectText: String, content: LegadoContentNode) throws {
        guard let object = LegadoEngineJSONParser.parse(objectText, lenient: true),
              let entries = object.objectEntries else {
            session.diagnostics.record(.ruleSyntax, "@put không đọc được: \(objectText.prefix(80))")
            return
        }
        for entry in entries {
            let rule = entry.value.scalarString
            let value = try evaluate(rule, kind: .string, content: content).finalString
            session.putRuleVariable(entry.key, value)
        }
    }

    func reportSelectorError(_ message: String) {
        session.diagnostics.record(.ruleSyntax, message)
    }
}
