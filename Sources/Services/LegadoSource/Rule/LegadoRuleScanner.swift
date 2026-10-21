import Foundation

/// Bộ quét cú pháp rule nguồn Legado, không đánh giá gì: tách phân đoạn `<js>`/`@js:` (spec §2.2), tách toán tử
/// `||`/`&&`/`%%` ở mức ngoài cùng (§2.5), tách đuôi regex `##` (§2.6), bóc `@put:{…}` (§2.10) và tách mẫu
/// `{{…}}` / `{$.x}` / `@get:{k}` (§2.7).
///
/// Quét trên byte UTF-8: mọi dấu hiệu đều là ASCII nên không cắt nhầm giữa ký tự nhiều byte.
enum LegadoRuleScanner {
    enum Segment {
        case rule(String)
        case js(String)
    }

    enum TemplatePart {
        case text(String)
        /// Nội dung bên trong `{{…}}` (đã trim).
        case expression(String)
        /// Đường dẫn `$.x` của placeholder một ngoặc `{$.x}`.
        case jsonPath(String)
        /// Khoá của `@get:{khoá}`.
        case variable(String)
    }

    /// Đuôi regex của một lá: `##R`, `##R##P`, `##R##P###`.
    struct RegexTail {
        var pattern: String
        var replacement: String?
        var firstMatchOnly: Bool
        var ignoredParts: Int
    }

    // MARK: - Phân đoạn (§2.2)

    static func segments(_ rule: String) -> [Segment] {
        let bytes = Array(rule.utf8)
        var output: [Segment] = []
        var ruleStart = 0
        var index = 0
        func flushRule(until end: Int) {
            guard end > ruleStart else { return }
            let text = string(bytes, ruleStart, end).trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { output.append(.rule(text)) }
        }
        while index < bytes.count {
            if bytes[index] == brace, index + 1 < bytes.count, bytes[index + 1] == brace,
               let end = balancedEnd(bytes, from: index) {
                index = end
                continue
            }
            if matchesCI(bytes, at: index, jsOpen) {
                flushRule(until: index)
                let codeStart = index + jsOpen.count
                if let close = findCI(bytes, jsClose, from: codeStart) {
                    output.append(.js(string(bytes, codeStart, close)))
                    index = close + jsClose.count
                } else {
                    output.append(.js(string(bytes, codeStart, bytes.count)))
                    index = bytes.count
                }
                ruleStart = index
                continue
            }
            if matchesCI(bytes, at: index, jsPrefix) {
                flushRule(until: index)
                output.append(.js(string(bytes, index + jsPrefix.count, bytes.count)))
                ruleStart = bytes.count
                index = bytes.count
                break
            }
            index += 1
        }
        flushRule(until: bytes.count)
        return output
    }

    // MARK: - Toán tử (§2.5)

    /// Tách theo `token` ở mức ngoài cùng; mỗi phần được trim. Luôn trả ít nhất một phần.
    static func split(_ text: String, by token: String) -> [String] {
        let bytes = Array(text.utf8)
        let positions = topLevelPositions(of: Array(token.utf8), in: bytes, firstOnly: false)
        guard !positions.isEmpty else { return [text.trimmingCharacters(in: .whitespacesAndNewlines)] }
        var parts: [String] = []
        var start = 0
        for position in positions {
            parts.append(string(bytes, start, position).trimmingCharacters(in: .whitespacesAndNewlines))
            start = position + token.utf8.count
        }
        parts.append(string(bytes, start, bytes.count).trimmingCharacters(in: .whitespacesAndNewlines))
        return parts
    }

    /// Vị trí của `token` ở mức ngoài cùng: bỏ qua ký tự sau `\`, vùng `[…]`, `(…)`, `{…}`/`{{…}}`, và chuỗi nháy
    /// **bên trong** ngoặc nhọn (nháy lẻ trong regex ở mức ngoài không được tính là mở chuỗi).
    static func topLevelPositions(of token: [UInt8], in bytes: [UInt8], firstOnly: Bool) -> [Int] {
        guard !token.isEmpty else { return [] }
        var positions: [Int] = []
        var index = 0
        var inSquare = false
        var paren = 0
        var curly = 0
        var quote: UInt8 = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte == backslash {
                index += 2
                continue
            }
            if quote != 0 {
                if byte == quote { quote = 0 }
                index += 1
                continue
            }
            if inSquare {
                if byte == closeSquare { inSquare = false }
                index += 1
                continue
            }
            if paren == 0, curly == 0, matches(bytes, at: index, token) {
                positions.append(index)
                if firstOnly { return positions }
                index += token.count
                continue
            }
            switch byte {
            case openSquare: inSquare = true
            case openParen: paren += 1
            case closeParen: paren = max(0, paren - 1)
            case brace: curly += 1
            case closeBrace: curly = max(0, curly - 1)
            case doubleQuote, singleQuote: if curly > 0 { quote = byte }
            default: break
            }
            index += 1
        }
        return positions
    }

    // MARK: - Đuôi regex (§2.6)

    /// Tách phần-chọn và đuôi regex tại `##` đầu tiên ở mức ngoài cùng. Ngoặc trong phần-chọn không cân thì
    /// rơi về `##` đầu tiên ngoài `{{…}}`.
    static func splitRegexTail(_ leaf: String) -> (selector: String, tail: RegexTail?) {
        let bytes = Array(leaf.utf8)
        let hashes = Array("##".utf8)
        var position = topLevelPositions(of: hashes, in: bytes, firstOnly: true).first
        if position == nil {
            position = firstOutsideDoubleBrace(hashes, in: bytes)
        }
        guard let split = position else { return (leaf, nil) }
        let selector = string(bytes, 0, split)
        let tailText = string(bytes, split + 2, bytes.count)
        var parts = tailText.components(separatedBy: "##")
        var firstOnly = false
        if parts.count >= 2, parts.last == "#" {
            firstOnly = true
            parts.removeLast()
        }
        let tail = RegexTail(
            pattern: parts.first ?? "",
            replacement: parts.count > 1 ? parts[1] : (firstOnly ? "" : nil),
            firstMatchOnly: firstOnly,
            ignoredParts: max(0, parts.count - 2)
        )
        return (selector, tail)
    }

    private static func firstOutsideDoubleBrace(_ token: [UInt8], in bytes: [UInt8]) -> Int? {
        var index = 0
        while index < bytes.count {
            if bytes[index] == brace, index + 1 < bytes.count, bytes[index + 1] == brace,
               let end = balancedEnd(bytes, from: index) {
                index = end
                continue
            }
            if matches(bytes, at: index, token) { return index }
            index += 1
        }
        return nil
    }

    // MARK: - @put (§2.10)

    /// Bóc mọi `@put:{…}` khỏi lá; trả phần còn lại và văn bản object của từng `@put`.
    static func extractPuts(_ leaf: String) -> (rest: String, puts: [String]) {
        var bytes = Array(leaf.utf8)
        var puts: [String] = []
        var searchFrom = 0
        while let start = findCI(bytes, putPrefix, from: searchFrom) {
            let objectStart = start + putPrefix.count - 1
            guard let end = balancedEnd(bytes, from: objectStart) else { break }
            puts.append(string(bytes, objectStart, end))
            bytes.removeSubrange(start..<end)
            searchFrom = start
        }
        return (String(decoding: bytes, as: UTF8.self), puts)
    }

    // MARK: - Mẫu (§2.7)

    static func containsPlaceholder(_ text: String) -> Bool {
        text.contains("{{") || text.contains("{$.") || text.contains("{$[")
            || text.range(of: "@get:{", options: .caseInsensitive) != nil
    }

    /// Placeholder trong **mã JS** của rule trường (§2.7): chỉ `{{…}}` và `@get:{k}`.
    static func containsScriptPlaceholder(_ text: String) -> Bool {
        text.contains("{{") || text.range(of: "@get:{", options: .caseInsensitive) != nil
    }

    /// `allowsSingleBrace = false` cho **mã JS**: chỉ nhận `{{…}}` và `@get:{k}` — `{$.x}` trong JS thường là mã thật
    /// (`function(){$.ajax(…)}`), không phải placeholder.
    static func templateParts(_ text: String, allowsSingleBrace: Bool = true) -> [TemplatePart] {
        let bytes = Array(text.utf8)
        var parts: [TemplatePart] = []
        var textStart = 0
        var index = 0
        func flushText(_ end: Int) {
            if end > textStart { parts.append(.text(string(bytes, textStart, end))) }
        }
        while index < bytes.count {
            if bytes[index] == brace, index + 1 < bytes.count, bytes[index + 1] == brace,
               let end = balancedEnd(bytes, from: index) {
                flushText(index)
                let inner = string(bytes, index + 2, end - 2).trimmingCharacters(in: .whitespacesAndNewlines)
                parts.append(.expression(inner))
                index = end
                textStart = end
                continue
            }
            if allowsSingleBrace, bytes[index] == brace, index + 2 < bytes.count, bytes[index + 1] == dollar,
               bytes[index + 2] == dot || bytes[index + 2] == openSquare,
               let end = balancedEnd(bytes, from: index) {
                flushText(index)
                parts.append(.jsonPath(string(bytes, index + 1, end - 1)))
                index = end
                textStart = end
                continue
            }
            if matchesCI(bytes, at: index, getPrefix),
               let close = bytes[(index + getPrefix.count)...].firstIndex(of: closeBrace) {
                flushText(index)
                parts.append(.variable(string(bytes, index + getPrefix.count, close).trimmingCharacters(in: .whitespaces)))
                index = close + 1
                textStart = index
                continue
            }
            index += 1
        }
        flushText(bytes.count)
        return parts
    }

    /// Vị trí ngay **sau** ngoặc đóng cân với ngoặc `{` tại `start` (đếm ngoặc, bỏ qua chuỗi nháy).
    static func balancedEnd(_ bytes: [UInt8], from start: Int) -> Int? {
        var depth = 0
        var quote: UInt8 = 0
        var index = start
        while index < bytes.count {
            let byte = bytes[index]
            if quote != 0 {
                if byte == backslash { index += 1 } else if byte == quote { quote = 0 }
            } else if byte == doubleQuote || byte == singleQuote || byte == backtick {
                quote = byte
            } else if byte == brace {
                depth += 1
            } else if byte == closeBrace {
                depth -= 1
                if depth == 0 { return index + 1 }
            }
            index += 1
        }
        return nil
    }

    // MARK: - Tiện ích byte

    static func string(_ bytes: [UInt8], _ start: Int, _ end: Int) -> String {
        guard start < end, start >= 0, end <= bytes.count else { return "" }
        return String(decoding: bytes[start..<end], as: UTF8.self)
    }

    static func matches(_ bytes: [UInt8], at index: Int, _ token: [UInt8]) -> Bool {
        guard index + token.count <= bytes.count else { return false }
        for offset in 0..<token.count where bytes[index + offset] != token[offset] {
            return false
        }
        return true
    }

    /// So không phân biệt hoa thường; `token` phải viết thường.
    static func matchesCI(_ bytes: [UInt8], at index: Int, _ token: [UInt8]) -> Bool {
        guard index + token.count <= bytes.count else { return false }
        for offset in 0..<token.count {
            var byte = bytes[index + offset]
            if byte >= 65 && byte <= 90 { byte += 32 }
            if byte != token[offset] { return false }
        }
        return true
    }

    static func findCI(_ bytes: [UInt8], _ token: [UInt8], from start: Int) -> Int? {
        guard start >= 0 else { return nil }
        var index = start
        while index + token.count <= bytes.count {
            if matchesCI(bytes, at: index, token) { return index }
            index += 1
        }
        return nil
    }

    static let jsOpen = Array("<js>".utf8)
    static let jsClose = Array("</js>".utf8)
    static let jsPrefix = Array("@js:".utf8)
    static let putPrefix = Array("@put:{".utf8)
    static let getPrefix = Array("@get:{".utf8)
    static let brace = UInt8(ascii: "{")
    static let closeBrace = UInt8(ascii: "}")
    static let openSquare = UInt8(ascii: "[")
    static let closeSquare = UInt8(ascii: "]")
    static let openParen = UInt8(ascii: "(")
    static let closeParen = UInt8(ascii: ")")
    static let backslash = UInt8(ascii: "\\")
    static let doubleQuote = UInt8(ascii: "\"")
    static let singleQuote = UInt8(ascii: "'")
    static let backtick = UInt8(ascii: "`")
    static let dollar = UInt8(ascii: "$")
    static let dot = UInt8(ascii: ".")
}
