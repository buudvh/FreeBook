import Foundation
import SwiftSoup

/// Bộ điều phối bóc tách — tương ứng `AnalyzeRule` của Legado.
///
/// Nhận chuỗi rule thô, biên dịch (có cache), chạy tuần tự từng đoạn, mỗi đoạn lấy kết quả của đoạn
/// trước làm dữ liệu vào. Phụ trách luôn nội suy `{{…}}` / `@get:{…}`, chạy `@put:{…}`, và áp
/// `##regex##replacement`.
public final class LegadoRuleEvaluator {
    private let baseUrl: String
    private let variables: LegadoVariableBag
    private let jsRuntime: LegadoJSRuntime
    private let isJSONResponse: Bool

    public private(set) var unsupportedFeatures: Set<LegadoUnsupportedFeature> = []

    public init(
        baseUrl: String,
        variables: LegadoVariableBag,
        jsRuntime: LegadoJSRuntime,
        isJSONResponse: Bool
    ) {
        self.baseUrl = baseUrl
        self.variables = variables
        self.jsRuntime = jsRuntime
        self.isJSONResponse = isJSONResponse
    }

    // MARK: - API

    /// Một chuỗi kết quả (nhiều dòng được nối bằng `\n`, giống `AnalyzeRule.getString`).
    public func string(_ rawRule: String?, on context: LegadoRuleContext) -> String? {
        let values = stringList(rawRule, on: context)
        if values.isEmpty { return nil }
        if values.count == 1 { return values[0] }
        return values.joined(separator: "\n")
    }

    /// Chuỗi kết quả và resolve thành URL tuyệt đối — dùng cho `bookUrl`, `coverUrl`, `chapterUrl`.
    ///
    /// **Lấy giá trị đầu tiên, không nối cả danh sách.** Một rule như `a@href` trên một thẻ `<li>` rất
    /// hay khớp nhiều `<a>` (link truyện, link tác giả, link chương mới); nối chúng bằng `\n` rồi
    /// resolve sẽ ra một URL rác kiểu `https://x.com/ read/1/ /author/y /read/1/p2.html` và server trả
    /// 404. Legado gọi `getString0` (phần tử đầu) đúng cho trường hợp `isUrl` (`AnalyzeRule.kt:384`).
    public func url(_ rawRule: String?, on context: LegadoRuleContext) -> String? {
        guard let first = stringList(rawRule, on: context).first?
            .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty else { return nil }
        // Giữ nguyên khối tuỳ chọn `,{…}`: nó là phần của "địa chỉ" theo nghĩa của Legado và phải
        // sống tới lúc gọi mạng (`BookChapter.kt:174-176` cũng chỉ tách khi absolutize).
        let (address, hasOption) = splitOption(first)
        let resolved = LegadoUrlBuilder.resolve(address, baseUrl: baseUrl)
        return hasOption ? resolved + String(first.dropFirst(address.count)) : resolved
    }

    public func stringList(_ rawRule: String?, on context: LegadoRuleContext) -> [String] {
        guard let rawRule, !rawRule.isEmpty else { return [] }
        let segments = LegadoRuleCompiler.compile(rawRule, isJSONResponse: isJSONResponse)
        guard !segments.isEmpty else { return [] }

        var current: LegadoRuleContext? = context
        var values: [String] = []

        for (offset, segment) in segments.enumerated() {
            guard let input = current else { break }
            runPutRules(segment.putMap, on: input)

            let isFirst = offset == 0
            let produced = apply(segment, on: input, isFirstSegment: isFirst)
            values = produced.map { applyReplacement(segment, to: $0) }
                .filter { !$0.isEmpty }

            if offset < segments.count - 1 {
                let joined = values.joined(separator: "\n")
                current = joined.isEmpty ? nil : LegadoRuleContext.from(string: joined, baseUrl: baseUrl)
            }
        }
        return values
    }

    /// Danh sách phần tử để duyệt (`bookList`, `chapterList`).
    public func elements(_ rawRule: String?, on context: LegadoRuleContext) -> [LegadoRuleContext] {
        guard let rawRule, !rawRule.isEmpty else { return [] }
        let segments = LegadoRuleCompiler.compile(rawRule, isJSONResponse: isJSONResponse)
        guard let segment = segments.first else { return [] }
        runPutRules(segment.putMap, on: context)

        switch effectiveMode(of: segment, on: context) {
        case .standard:
            guard let element = context.htmlElement else { return [] }
            let rule = interpolate(segment.rule, on: context)
            return LegadoJsoupEngine.elements(rule: rule, on: element).map { .html($0) }

        case .json:
            guard let json = context.jsonValue else { return [] }
            let rule = interpolate(segment.rule, on: context)
            return LegadoJSONPath.list(rule, on: json).map { .json($0) }

        case .xpath:
            guard let element = context.htmlElement else { return [] }
            let rule = interpolate(segment.rule, on: context)
            let outcome = LegadoXPathEvaluator.evaluate(rule, on: element)
            if outcome.usedUnsupportedSyntax {
                unsupportedFeatures.insert(.xpathBeyondSubset)
            }
            return outcome.elements.map { .html($0) }

        case .regex:
            let rule = interpolate(segment.rule, on: context)
            let patterns = LegadoRuleLexer.split(rule, separator: "&&")
            return LegadoRegexExtractor.elements(in: context.stringValue, patterns: patterns)
                .map { groups in .text(groups.joined(separator: "\u{1}")) }

        case .js:
            let value = jsRuntime.evaluate(segment.rule, result: jsInput(for: context))
            adoptRuntimeDiagnostics()
            guard let value else { return [] }
            if value.isArray, let array = value.toArray() {
                return array.map { item in
                    if let text = item as? String {
                        return LegadoRuleContext.from(string: text, baseUrl: baseUrl)
                    }
                    return .json(item)
                }
            }
            guard let text = value.toString(), !text.isEmpty else { return [] }
            let produced = LegadoRuleContext.from(string: text, baseUrl: baseUrl)
            if let json = produced.jsonValue as? [Any] {
                return json.map { .json($0) }
            }
            return [produced]

        case .webJs:
            unsupportedFeatures.insert(.webJsRule)
            return []
        }
    }

    // MARK: - Một đoạn

    private func apply(
        _ segment: LegadoCompiledRule,
        on context: LegadoRuleContext,
        isFirstSegment: Bool
    ) -> [String] {
        switch effectiveMode(of: segment, on: context) {
        case .standard:
            guard let element = context.htmlElement else { return [] }
            let rule = interpolate(segment.rule, on: context)
            guard !rule.isEmpty else { return [] }
            return LegadoJsoupEngine.stringList(rule: rule, on: element)

        case .json:
            guard let json = context.jsonValue else { return [] }
            let rule = interpolate(segment.rule, on: context)
            guard !rule.isEmpty else { return [] }
            return LegadoJSONPath.stringList(rule, on: json)

        case .xpath:
            guard let element = context.htmlElement else { return [] }
            let rule = interpolate(segment.rule, on: context)
            guard !rule.isEmpty else { return [] }
            let outcome = LegadoXPathEvaluator.evaluate(rule, on: element)
            if outcome.usedUnsupportedSyntax {
                unsupportedFeatures.insert(.xpathBeyondSubset)
            }
            return outcome.strings

        case .regex:
            let rule = interpolate(segment.rule, on: context)
            let patterns = LegadoRuleLexer.split(rule, separator: "&&")
            let groups = LegadoRegexExtractor.elements(in: context.stringValue, patterns: patterns)
            // Nhóm bắt số 1 là quy ước phổ biến; không có thì lấy toàn bộ khớp.
            return groups.compactMap { $0.count > 1 ? $0[1] : $0.first }

        case .js:
            let input = isFirstSegment ? jsInput(for: context) : context.stringValue
            let result = jsRuntime.evaluateToStringList(segment.rule, result: input)
            adoptRuntimeDiagnostics()
            return result

        case .webJs:
            unsupportedFeatures.insert(.webJsRule)
            return []
        }
    }

    /// Chế độ thật của một đoạn rule, sau khi xét dữ liệu đang cầm.
    ///
    /// Rule **trần** (không tiền tố) mà dữ liệu là JSON thì phải hiểu là JSONPath: `ruleToc` của nguồn
    /// dựng danh sách chương bằng `@js:` trả về mảng object rồi khai `chapterName: "title"` — `title`
    /// là tên field JSON, không phải selector HTML.
    private func effectiveMode(
        of segment: LegadoCompiledRule,
        on context: LegadoRuleContext
    ) -> LegadoRuleMode {
        guard segment.mode == .standard, context.isJSON else { return segment.mode }
        return .json
    }

    private func applyReplacement(_ segment: LegadoCompiledRule, to value: String) -> String {
        guard let pattern = segment.replaceRegex, !pattern.isEmpty else { return value }
        return LegadoRegexExtractor.applyReplacement(
            to: value,
            pattern: pattern,
            replacement: segment.replacement,
            firstOnly: segment.replaceFirstOnly
        )
    }

    private func runPutRules(_ putMap: [String: String], on context: LegadoRuleContext) {
        guard !putMap.isEmpty else { return }
        for (key, rule) in putMap {
            // Rule con của `@put` được chạy như một rule bình thường trên cùng ngữ cảnh.
            if let value = string(rule, on: context), !value.isEmpty {
                variables.put(key, value)
            }
        }
    }

    private func jsInput(for context: LegadoRuleContext) -> Any {
        switch context {
        case .json(let value):
            return value
        default:
            return context.stringValue
        }
    }

    private func adoptRuntimeDiagnostics() {
        unsupportedFeatures.formUnion(jsRuntime.unsupportedFeatures)
    }

    // MARK: - Nội suy

    /// Thay `{{js}}` và `@get:{key}` trong chuỗi rule.
    ///
    /// Legado làm việc này lúc dựng rule; ở đây làm lúc chạy để rule biên dịch một lần vẫn dùng được
    /// cho nhiều truyện có túi biến khác nhau.
    public func interpolate(_ rule: String, on context: LegadoRuleContext? = nil) -> String {
        var result = rule

        if result.range(of: "@get:", options: .caseInsensitive) != nil {
            result = replaceGetMarkers(result)
        }

        guard result.contains("{{") else { return result }
        return LegadoRuleLexer.expandInner(result) { [weak self] inner in
            guard let self else { return "" }
            let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)
            // `{{…}}` chứa **rule** khi bắt đầu bằng `@`, `$.`, `$[`, `//` — Legado phân biệt bằng
            // `SourceRule.isRule` (`:818-823`). Còn lại mới là biểu thức JS.
            if Self.looksLikeRule(trimmed), let context {
                return self.string(trimmed, on: context) ?? ""
            }
            let input = context.map { self.jsInput(for: $0) } ?? ""
            guard let value = self.jsRuntime.evaluateToString(trimmed, result: input) else { return "" }
            return value
        }
    }

    private static func looksLikeRule(_ text: String) -> Bool {
        text.hasPrefix("@") || text.hasPrefix("$.") || text.hasPrefix("$[") || text.hasPrefix("//")
    }

    private func replaceGetMarkers(_ rule: String) -> String {
        var result = rule
        while let marker = result.range(of: "@get:", options: .caseInsensitive) {
            let tail = result[marker.upperBound...]
            guard tail.first == "{", let close = tail.firstIndex(of: "}") else { break }
            let key = String(tail[tail.index(after: tail.startIndex)..<close])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = variables.get(key)
            result.replaceSubrange(marker.lowerBound..<tail.index(after: close), with: value)
        }
        return result
    }

    private func splitOption(_ raw: String) -> (address: String, hasOption: Bool) {
        guard let range = raw.range(of: #"\s*,\s*(?=\{)"#, options: .regularExpression) else {
            return (raw, false)
        }
        return (String(raw[raw.startIndex..<range.lowerBound]), true)
    }
}
