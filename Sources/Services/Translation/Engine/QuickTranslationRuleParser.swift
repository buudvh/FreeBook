import Foundation

/// Text → `[QuickTranslationParsedRule]` + danh sách lỗi cú pháp.
///
/// Hỗ trợ đúng các định dạng dòng mà bộ rule vBook đang dùng: `pattern = replacement`,
/// `pattern=replacement`, `"pattern" = "replacement"` và phân tách bằng tab. Dòng trống, `#`, `//`,
/// `===` bị bỏ qua. Dòng non-comment không thuộc định dạng nào thành `UNPARSEABLE_RULE_LINE` (hard)
/// thay vì bỏ im lặng như reference — để không nạp thiếu mà không ai biết.
public enum QuickTranslationRuleParser {
    public struct Result {
        public var rules: [QuickTranslationParsedRule] = []
        public var issues: [QuickTranslationRuleIssue] = []
    }

    private struct ParseError: Error {
        let code: QuickTranslationRuleIssue.Code
        let message: String
    }

    // MARK: - Nhập văn bản

    public static func parse(_ text: String) -> Result {
        var result = Result()
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for (index, rawLine) in normalized.components(separatedBy: "\n").enumerated() {
            let sourceLine = index + 1
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("//") || trimmed.hasPrefix("===") {
                continue
            }

            guard let split = splitRuleLine(trimmed) else {
                result.issues.append(QuickTranslationRuleIssue(
                    sourceLine: sourceLine,
                    code: .unparseableRuleLine,
                    message: "Dòng không theo định dạng \"mẫu = bản dịch\"",
                    rawLine: rawLine
                ))
                continue
            }

            if split.pattern.isEmpty {
                result.issues.append(QuickTranslationRuleIssue(
                    sourceLine: sourceLine,
                    code: .emptyPattern,
                    message: "Mẫu (phần trước dấu =) không được để trống",
                    rawLine: rawLine
                ))
                continue
            }

            do {
                var captureCount = 0
                let elements = try parseElements(Array(split.pattern), captureCount: &captureCount)
                result.rules.append(QuickTranslationParsedRule(
                    sourceLine: sourceLine,
                    rawLine: rawLine,
                    pattern: split.pattern,
                    replacement: split.replacement,
                    elements: elements,
                    captureCount: captureCount
                ))
            } catch let error as ParseError {
                result.issues.append(QuickTranslationRuleIssue(
                    sourceLine: sourceLine,
                    code: error.code,
                    message: error.message,
                    rawLine: rawLine
                ))
            } catch {
                result.issues.append(QuickTranslationRuleIssue(
                    sourceLine: sourceLine,
                    code: .unparseableRuleLine,
                    message: "Không phân tích được mẫu",
                    rawLine: rawLine
                ))
            }
        }

        return result
    }

    // MARK: - Tách một dòng

    /// `internal` chứ không `private`: `QuickTranslationRuleFileEditor` phải hỏi **đúng** hàm này
    /// "khoá của dòng này là gì" khi sửa/xoá theo key. Cài lại logic tách ở chỗ thứ hai là mở đường
    /// cho hai nơi hiểu khác nhau về cùng một dòng (`"p"="r"`, tab, `unquote`).
    internal static func splitRuleLine(_ trimmed: String) -> (pattern: String, replacement: String)? {
        if trimmed.hasPrefix("\"") {
            let quoted = #"^"([^"]+)"\s*=\s*"([^"]*)"$"#
            if let regex = try? NSRegularExpression(pattern: quoted),
               let match = regex.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)),
               match.numberOfRanges == 3 {
                let nsTrimmed = trimmed as NSString
                return (
                    nsTrimmed.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces),
                    nsTrimmed.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespaces)
                )
            }
        }

        if let separator = trimmed.firstIndex(of: "="), separator != trimmed.startIndex {
            let pattern = unquote(String(trimmed[..<separator]).trimmingCharacters(in: .whitespaces))
            let replacement = unquote(String(trimmed[trimmed.index(after: separator)...]).trimmingCharacters(in: .whitespaces))
            if !pattern.isEmpty { return (pattern, replacement) }
        }

        if let tab = trimmed.firstIndex(of: "\t"), tab != trimmed.startIndex {
            let pattern = unquote(String(trimmed[..<tab]).trimmingCharacters(in: .whitespaces))
            let replacement = unquote(String(trimmed[trimmed.index(after: tab)...]).trimmingCharacters(in: .whitespaces))
            if !pattern.isEmpty { return (pattern, replacement) }
        }

        return nil
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else { return value }
        return String(value.dropFirst().dropLast())
    }

    // MARK: - Dựng AST

    /// Đọc một dãy phần tử tới hết `chars`, hoặc tới `)` khi `stopAtCloseParen` bật.
    /// Trả về cả vị trí dừng để nhánh group biết ăn tới đâu.
    private static func parseElements(
        _ chars: [Character],
        captureCount: inout Int
    ) throws -> [QuickTranslationRuleElement] {
        var cursor = 0
        let elements = try parseSequence(chars, from: &cursor, stopAtCloseParen: false, captureCount: &captureCount)
        guard cursor >= chars.count else {
            throw ParseError(code: .unbalancedParens, message: "Thừa dấu ')' trong mẫu")
        }
        return elements
    }

    private static func parseSequence(
        _ chars: [Character],
        from cursor: inout Int,
        stopAtCloseParen: Bool,
        captureCount: inout Int
    ) throws -> [QuickTranslationRuleElement] {
        var elements: [QuickTranslationRuleElement] = []

        while cursor < chars.count {
            let char = chars[cursor]

            if char == ")" {
                if stopAtCloseParen { return elements }
                throw ParseError(code: .unbalancedParens, message: "Thiếu dấu '(' cho ')' trong mẫu")
            }

            // Trong nhóm, `|` là ranh giới alternative; ngoài nhóm nó chỉ là ký tự thường.
            if char == "|", stopAtCloseParen {
                return elements
            }

            if char == "<" {
                let element = try parseToken(chars, from: &cursor, captureCount: &captureCount)
                elements.append(element)
                continue
            }

            if char == "(" {
                let element = try parseGroup(chars, from: &cursor, captureCount: &captureCount)
                elements.append(element)
                continue
            }

            // `\x` là escape ký tự thường (rule thật dùng `\[`, `\]`, `\+`).
            var literalChar = char
            if char == "\\", cursor + 1 < chars.count {
                cursor += 1
                literalChar = chars[cursor]
            }
            cursor += 1
            appendLiteral(literalChar, to: &elements)
        }

        if stopAtCloseParen {
            throw ParseError(code: .unbalancedParens, message: "Thiếu dấu ')' đóng nhóm trong mẫu")
        }
        return elements
    }

    private static func appendLiteral(_ char: Character, to elements: inout [QuickTranslationRuleElement]) {
        let units = Array(String(char).utf16)
        if let last = elements.indices.last,
           case .literal(let existing) = elements[last].kind,
           !elements[last].isOptional {
            elements[last].kind = .literal(existing + units)
            elements[last].minLength = existing.count + units.count
            elements[last].maxLength = elements[last].minLength
            return
        }
        elements.append(QuickTranslationRuleElement(
            kind: .literal(units),
            minLength: units.count,
            maxLength: units.count
        ))
    }

    private static func parseToken(
        _ chars: [Character],
        from cursor: inout Int,
        captureCount: inout Int
    ) throws -> QuickTranslationRuleElement {
        guard let close = chars[cursor...].firstIndex(of: ">") else {
            throw ParseError(code: .unbalancedParens, message: "Thiếu dấu '>' đóng token")
        }
        let spec = String(chars[(cursor + 1)..<close])
        cursor = close + 1

        var isOptional = false
        if cursor < chars.count, chars[cursor] == "?" {
            isOptional = true
            cursor += 1
        }

        let parts = spec.components(separatedBy: ":")
        let names = parts[0].components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty, !names.contains(where: { $0.isEmpty }) else {
            throw ParseError(code: .unknownTokenName, message: "Token <\(spec)> không có tên")
        }

        var minLength = 1
        var maxLength = 12
        if parts.count > 1, !parts[1].isEmpty {
            let bounds = parts[1].components(separatedBy: "-").compactMap { Int($0) }
            guard let first = bounds.first, first >= 1 else {
                throw ParseError(code: .unknownTokenName, message: "Khoảng độ dài của <\(spec)> không hợp lệ")
            }
            minLength = first
            maxLength = bounds.count > 1 ? max(first, bounds[1]) : first
        }

        let index = captureCount
        captureCount += 1

        if names.allSatisfy({ $0 == "n" || $0 == "y" }) {
            return QuickTranslationRuleElement(
                kind: .numeral(isDigitwise: names[0] == "y"),
                minLength: minLength,
                maxLength: maxLength,
                isOptional: isOptional,
                captureIndex: index
            )
        }

        if names.allSatisfy({ $0 == "L" }) {
            // Header: `<L>` là **một** nhãn chương. Reference để `{1,12}` và trả nguyên văn khi
            // capture ≥ 2 ký tự — đó là rác, nên cố định 1 ký tự (lệch có chủ ý).
            return QuickTranslationRuleElement(
                kind: .chapterLabel,
                minLength: 1,
                maxLength: 1,
                isOptional: isOptional,
                captureIndex: index
            )
        }

        var kinds: [QuickTranslationRuleElement.DictionaryKind] = []
        for name in names {
            switch name {
            case "w":
                kinds.append(contentsOf: [.name, .pronoun, .vietPhrase])
            case "ne", "pn", "vp", "hv":
                guard let kind = QuickTranslationRuleElement.DictionaryKind(rawValue: name) else {
                    throw ParseError(code: .unknownTokenName, message: "Token <\(name)> không được hỗ trợ")
                }
                kinds.append(kind)
            default:
                throw ParseError(code: .unknownTokenName, message: "Token <\(name)> không được hỗ trợ")
            }
        }

        // `<hv>` là đúng một ký tự Hán theo header, không nhận range.
        if kinds == [.hanViet] {
            minLength = 1
            maxLength = 1
        }

        return QuickTranslationRuleElement(
            kind: .dictionary(kinds),
            minLength: minLength,
            maxLength: maxLength,
            isOptional: isOptional,
            captureIndex: index
        )
    }

    private static func parseGroup(
        _ chars: [Character],
        from cursor: inout Int,
        captureCount: inout Int
    ) throws -> QuickTranslationRuleElement {
        cursor += 1 // bỏ '('
        var alternatives: [[QuickTranslationRuleElement]] = []

        while true {
            let alternative = try parseSequence(chars, from: &cursor, stopAtCloseParen: true, captureCount: &captureCount)
            alternatives.append(alternative)

            guard cursor < chars.count else {
                throw ParseError(code: .unbalancedParens, message: "Thiếu dấu ')' đóng nhóm trong mẫu")
            }
            if chars[cursor] == "|" {
                cursor += 1
                continue
            }
            break
        }

        cursor += 1 // bỏ ')'
        var isOptional = false
        if cursor < chars.count, chars[cursor] == "?" {
            isOptional = true
            cursor += 1
        }

        return QuickTranslationRuleElement(
            kind: .group(alternatives),
            minLength: 0,
            maxLength: 0,
            isOptional: isOptional
        )
    }
}
