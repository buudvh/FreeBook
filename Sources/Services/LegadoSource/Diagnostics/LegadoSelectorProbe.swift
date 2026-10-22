import Foundation

/// **Đầu dò bộ chọn**: bằng chứng để phân biệt "nguồn lỗi thời" với "nghi do app" khi một bước danh sách/nội dung ra
/// rỗng dù trang tải được.
///
/// Lấy token class/id/thẻ của rule (`LegadoRuleSelectorTokens`), đếm trong **toàn bộ** HTML trang bằng thuộc tính
/// `class="…"` (so **nguyên từ**, class nhiều từ = đủ mọi từ trên cùng phần tử) / `id="…"` (so bằng) / `<thẻ` — không
/// dựng DOM. Vế rule kết thúc bằng thẻ trần (`.list li`, `id.list@tag.dd`) còn phải thấy thẻ đó **sau** phần tử chứa
/// (trong `trailingTagWindow` ký tự) — trang tìm kiếm không có kết quả vẫn có khung `.list` rỗng. Trang có cấu trúc mà
/// rule nhắm tới nhưng engine ra 0 ⇒ nghi app; không có token nào ⇒ trang đã đổi giao diện.
///
/// Chỉ chạy khi lượt chạy có `LegadoRunLog` (bộ nghiệm thu, màn gỡ lỗi) **và** bước ra rỗng — app thường không trả giá
/// nào. Không giữ HTML: chỉ số đếm, mã HTTP, kích thước và dấu hiệu trang chặn/thử thách (`LegadoPageMarker`).
struct LegadoSelectorProbe: Sendable, Equatable {
    enum TokenKind: String, Sendable {
        case className = "class"
        case id
        case tag
    }

    struct Token: Sendable, Equatable {
        let kind: TokenKind
        /// Class nhiều từ cách nhau dấu cách (phải đủ mọi class trên cùng phần tử).
        let name: String
        var count: Int = 0

        /// `.a.b` / `#x` / `<li>`.
        var label: String {
            switch kind {
            case .className: return "." + name.split(separator: " ").joined(separator: ".")
            case .id: return "#" + name
            case .tag: return "<\(name)>"
            }
        }
    }

    /// Một vế `||`/`&&`/`%%` của rule.
    struct Leaf: Sendable, Equatable {
        var tokens: [Token]
        /// Thẻ của phần chọn cuối khi nó không có class/id (`li` trong `.list li`, `dd` trong `id.list@tag.dd`).
        var trailingTag: String?
        /// Thẻ cuối có xuất hiện sau phần tử chứa (token class/id cuối của vế) không; `nil` khi không cần/không đo.
        var trailingTagFound: Bool?

        var selectorTokens: [Token] { tokens.filter { $0.kind != .tag } }
    }

    /// Cửa sổ (ký tự UTF-16) sau phần tử chứa để tìm thẻ cuối.
    static let trailingTagWindow = 65_536
    static let ruleClipLength = 200

    /// `bookList` / `chapterList` / `content`.
    let field: String
    /// Rule đã dò (rút gọn `ruleClipLength` ký tự) — chỉ giữ trong bộ nhớ của lượt chạy.
    let rule: String
    let isList: Bool
    /// Mã HTTP của **chính** trang mà rule chạy trên (WebView luôn báo 200).
    let statusCode: Int
    let byteCount: Int
    /// Thân là JSON ⇒ không dò (rule JSONPath ngầm như `data.books` sẽ ra token giả).
    let isJSON: Bool
    /// Số phần tử rule danh sách khớp **trước** khi lọc mục thiếu tên/link; `nil` với trường chuỗi.
    let matchedElements: Int?
    /// Các vế của rule (token đã đếm).
    let leaves: [Leaf]
    /// Rule có JS sau phần bộ chọn (JS có thể tự lọc hết).
    let hasScript: Bool
    /// Trường nội dung: số ký tự chữ (bỏ thẻ/script) bên trong phần tử đầu tiên khớp token — `nil` khi không đo.
    let elementTextLength: Int?
    let marker: LegadoPageMarker?
    /// Trang ngắn chỉ để báo lỗi bằng `alert("…")` (vd "关键字最少 10 个字符" — web chê từ khoá): câu báo, `nil` khi không có.
    let alertMessage: String?

    // MARK: - Kết luận từ số đếm

    var isPageLoaded: Bool { (200..<300).contains(statusCode) }

    /// Vế có token class/id (thẻ trần như `li`, `a` trang nào cũng có — không phải bằng chứng).
    var selectorLeaves: [Leaf] {
        leaves.filter { !$0.selectorTokens.isEmpty }
    }

    var hasSelectorTokens: Bool { !selectorLeaves.isEmpty }

    /// Token class/id có trong trang (không trùng).
    var presentTokens: [Token] {
        var seen = Set<String>()
        return selectorLeaves.flatMap { $0.selectorTokens }.filter { $0.count > 0 && seen.insert($0.label).inserted }
    }

    /// Token class/id không có trong trang (không trùng).
    var missingTokens: [Token] {
        var seen = Set<String>()
        return selectorLeaves.flatMap { $0.selectorTokens }.filter { $0.count == 0 && seen.insert($0.label).inserted }
    }

    /// Có một vế mà **mọi** token class/id đều có trong trang **và** thẻ cuối (nếu có) xuất hiện sau phần tử chứa.
    var hasStructureMatch: Bool {
        selectorLeaves.contains { leaf in
            leaf.selectorTokens.allSatisfy { $0.count > 0 } && leaf.trailingTagFound != false
        }
    }

    /// Vế có đủ class/id nhưng **không** thấy thẻ cuối sau phần tử chứa (khung rỗng) — thẻ đó, để nêu trong lý do.
    var missingTrailingTag: String? {
        selectorLeaves.first { leaf in
            leaf.selectorTokens.allSatisfy { $0.count > 0 } && leaf.trailingTagFound == false
        }?.trailingTag
    }

    /// Một dòng cho thẻ gỡ lỗi: "có .bookbox ×12 · không có #list".
    var summary: String {
        var parts: [String] = []
        let present = presentTokens.prefix(4).map { "\($0.label) ×\($0.count)" }
        if !present.isEmpty { parts.append("có " + present.joined(separator: ", ")) }
        let missing = missingTokens.prefix(4).map(\.label)
        if !missing.isEmpty { parts.append("không có " + missing.joined(separator: ", ")) }
        if let tag = missingTrailingTag { parts.append("không thấy <\(tag)> bên trong") }
        if parts.isEmpty { parts.append(isJSON ? "trang JSON — không dò" : "rule không có class/id để dò") }
        if let matchedElements { parts.append("rule khớp \(matchedElements) phần tử") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Ghi từ code luồng

    /// Gọi từ code luồng (thread engine) khi một bước ra rỗng. Không có log gắn với `session` ⇒ không làm gì.
    static func record(
        in session: LegadoEngineSession,
        field: String,
        rule: String,
        response: LegadoHTTPResponse,
        matchedElements: Int?
    ) {
        guard let log = LegadoRunLog.bound(to: session) else { return }
        log.recordProbe(inspect(field: field, rule: rule, isList: matchedElements != nil, statusCode: response.statusCode,
                                body: response.body, matchedElements: matchedElements))
    }

    // MARK: - Hàm thuần

    static func inspect(
        field: String,
        rule: String,
        isList: Bool,
        statusCode: Int,
        body: String,
        matchedElements: Int?
    ) -> LegadoSelectorProbe {
        let byteCount = body.utf8.count
        let marker = LegadoPageMarker.detect(body: body, statusCode: statusCode, byteCount: byteCount)
        let head = body.drop(while: { $0.isWhitespace || $0 == "\u{FEFF}" }).first
        let isJSON = head == "{" || head == "["
        let parsed = LegadoRuleSelectorTokens.parse(rule, isList: isList)
        var leaves = parsed.leaves
        var textLength: Int?
        if !isJSON, !leaves.isEmpty {
            let counted = countTokens(leaves, in: body as NSString, measureText: !isList)
            leaves = counted.leaves
            textLength = counted.textLength
        }
        return LegadoSelectorProbe(
            field: field,
            rule: String(rule.trimmingCharacters(in: .whitespacesAndNewlines).prefix(ruleClipLength)),
            isList: isList,
            statusCode: statusCode,
            byteCount: byteCount,
            isJSON: isJSON,
            matchedElements: matchedElements,
            leaves: isJSON ? [] : leaves,
            hasScript: parsed.hasScript,
            elementTextLength: textLength,
            marker: marker,
            alertMessage: byteCount <= alertPageBytes ? alertText(in: body) : nil
        )
    }

    /// Trang lớn hơn mức này không coi là "trang chỉ để báo lỗi bằng alert".
    static let alertPageBytes = 4_096
    private static let alertPattern = try? NSRegularExpression(
        pattern: #"alert\(\s*["'`]([^"'`]{1,200})["'`]\s*\)"#, options: []
    )

    /// Câu trong `alert("…")` đầu tiên của trang (đã gọn khoảng trắng).
    static func alertText(in body: String) -> String? {
        let text = body as NSString
        guard let pattern = alertPattern,
              let match = pattern.firstMatch(in: body, range: NSRange(location: 0, length: text.length)),
              match.range(at: 1).location != NSNotFound else { return nil }
        let message = text.substring(with: match.range(at: 1))
            .components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        return message.isEmpty ? nil : message
    }

    private static let classPattern = try? NSRegularExpression(
        pattern: #"(?<![\w-])class\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#, options: [.caseInsensitive]
    )
    private static let idPattern = try? NSRegularExpression(
        pattern: #"(?<![\w-])id\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))"#, options: [.caseInsensitive]
    )

    /// Đếm token trong HTML, đo thẻ cuối sau phần tử chứa. `measureText` ⇒ đo thêm số ký tự chữ trong phần tử đầu tiên
    /// khớp một token class/id.
    private static func countTokens(_ leaves: [Leaf], in html: NSString, measureText: Bool) -> (leaves: [Leaf], textLength: Int?) {
        let fullRange = NSRange(location: 0, length: html.length)
        var classCounts: [String: Int] = [:]
        var idCounts: [String: Int] = [:]
        // Vị trí thuộc tính khớp đầu tiên, khoá `locationKey`.
        var firstLocation: [String: Int] = [:]
        let allTokens = leaves.flatMap { $0.tokens }
        let classTokens = Set(allTokens.filter { $0.kind == .className }.map(\.name))
        let idTokens = Set(allTokens.filter { $0.kind == .id }.map(\.name))

        if !classTokens.isEmpty {
            let wanted = classTokens.map { ($0, Set($0.split(separator: " ").map(String.init))) }
            classPattern?.enumerateMatches(in: html as String, options: [], range: fullRange) { match, _, _ in
                guard let match, let value = attributeValue(match, in: html) else { return }
                let words = Set(value.split(whereSeparator: { $0.isWhitespace }).map(String.init))
                for (name, required) in wanted where required.isSubset(of: words) {
                    classCounts[name, default: 0] += 1
                    let key = locationKey(.className, name)
                    if firstLocation[key] == nil { firstLocation[key] = match.range.location }
                }
            }
        }
        if !idTokens.isEmpty {
            idPattern?.enumerateMatches(in: html as String, options: [], range: fullRange) { match, _, _ in
                guard let match, let value = attributeValue(match, in: html) else { return }
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                guard idTokens.contains(trimmed) else { return }
                idCounts[trimmed, default: 0] += 1
                let key = locationKey(.id, trimmed)
                if firstLocation[key] == nil { firstLocation[key] = match.range.location }
            }
        }

        var measuredAt: Int?
        var counted: [Leaf] = []
        for leaf in leaves {
            var output = leaf
            output.tokens = leaf.tokens.map { token in
                var copy = token
                switch token.kind {
                case .className: copy.count = classCounts[token.name] ?? 0
                case .id: copy.count = idCounts[token.name] ?? 0
                case .tag: copy.count = tagLocations(token.name, in: html, from: 0, length: html.length).count
                }
                return copy
            }
            let present = output.selectorTokens.filter { $0.count > 0 }
            if measuredAt == nil, let first = present.first { measuredAt = firstLocation[locationKey(first.kind, first.name)] }
            // Thẻ cuối phải nằm sau phần tử chứa (token class/id cuối của vế).
            if let tag = output.trailingTag, output.selectorTokens.allSatisfy({ $0.count > 0 }),
               let container = output.selectorTokens.last,
               let start = firstLocation[locationKey(container.kind, container.name)] {
                let length = min(trailingTagWindow, html.length - start)
                output.trailingTagFound = !tagLocations(tag, in: html, from: start, length: length).isEmpty
            }
            counted.append(output)
        }
        let textLength = measureText ? measuredAt.map { innerTextLength(in: html, attributeLocation: $0) } : nil
        return (counted, textLength)
    }

    private static func locationKey(_ kind: TokenKind, _ name: String) -> String {
        kind.rawValue + ":" + name
    }

    private static func attributeValue(_ match: NSTextCheckingResult, in html: NSString) -> String? {
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location != NSNotFound { return html.substring(with: range) }
        }
        return nil
    }

    /// Vị trí các thẻ mở `<tag` trong đoạn `[from, from + length)`.
    private static func tagLocations(_ tag: String, in html: NSString, from: Int, length: Int) -> [Int] {
        let pattern = "<" + NSRegularExpression.escapedPattern(for: tag) + #"(?=[\s>/])"#
        guard length > 0, let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: html as String, options: [], range: NSRange(location: from, length: length))
            .map { $0.range.location }
    }

    /// Số ký tự chữ (bỏ script/style/thẻ/khoảng trắng) từ sau thẻ mở chứa thuộc tính ở `attributeLocation` tới thẻ
    /// đóng **cùng tên đầu tiên** (phần tử lồng cùng tên ⇒ đếm thiếu — nghiêng về "chưa rõ"), tối đa 20 000 ký tự.
    private static func innerTextLength(in html: NSString, attributeLocation: Int) -> Int {
        let open = html.range(of: "<", options: .backwards, range: NSRange(location: 0, length: attributeLocation))
        guard open.location != NSNotFound else { return 0 }
        let tagRange = NSRange(location: open.location + 1, length: min(20, html.length - open.location - 1))
        let tagName = String(html.substring(with: tagRange).prefix { $0.isLetter || $0.isNumber })
        let close = html.range(of: ">", options: [], range: NSRange(location: attributeLocation,
                                                                     length: html.length - attributeLocation))
        guard !tagName.isEmpty, close.location != NSNotFound else { return 0 }
        let start = close.location + 1
        let searchLength = min(html.length - start, 20_000)
        guard searchLength > 0 else { return 0 }
        let end = html.range(of: "</" + tagName, options: [.caseInsensitive],
                             range: NSRange(location: start, length: searchLength))
        let length = end.location == NSNotFound ? searchLength : end.location - start
        var inner = html.substring(with: NSRange(location: start, length: length))
        for pattern in [#"<script[\s\S]*?</script>"#, #"<style[\s\S]*?</style>"#, #"<[^>]*>"#, #"&[#\w]+;"#] {
            inner = inner.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        return inner.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }.count
    }
}
