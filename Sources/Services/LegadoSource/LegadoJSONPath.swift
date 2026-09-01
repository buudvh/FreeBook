import Foundation

/// Tập con JSONPath đủ cho nguồn Legado — thay cho `com.jayway.jsonpath`.
///
/// Cú pháp hỗ trợ:
/// * `$.a.b`, `$['a']['b']` — đi vào khoá.
/// * `$.a[0]`, `$.a[-1]`, `$.a[*]`, `$.a[0,2]`, `$.a[1:3]` — chỉ số, danh sách, khoảng (nửa mở như
///   JSONPath chuẩn), số âm tính từ cuối.
/// * `$..a` — quét đệ quy.
/// * `$.a[?(@.b == 'c')]` — lọc theo so sánh `==`, `!=`, `>`, `<`, `>=`, `<=` và `=~` (regex).
/// * `$.a.length()` — số phần tử.
/// * Nhiều đường dẫn ghép bằng `&&` hoặc `||` (Legado cho phép, xử lý ở `LegadoRuleEvaluator`).
///
/// Không hỗ trợ: hàm tổng hợp (`min()`, `sum()`…), script expression `$[(@.length-1)]`. Gặp thì trả
/// rỗng và caller ghi `LegadoUnsupportedFeature`.
public enum LegadoJSONPath {

    /// Trả về danh sách giá trị thô (`String`, `NSNumber`, `[Any]`, `[String: Any]`).
    public static func evaluate(_ path: String, on root: Any) -> [Any] {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var expression = trimmed
        if expression.hasPrefix("$") {
            expression.removeFirst()
        }
        return walk(tokens: tokenize(expression), values: [root])
    }

    /// Giá trị đầu tiên đổi thành chuỗi.
    public static func string(_ path: String, on root: Any) -> String? {
        stringList(path, on: root).first
    }

    /// Mọi giá trị đổi thành chuỗi, mảng được **làm phẳng** một cấp.
    public static func stringList(_ path: String, on root: Any) -> [String] {
        var result: [String] = []
        for value in evaluate(path, on: root) {
            if let list = value as? [Any] {
                for item in list {
                    if let text = scalarString(item) { result.append(text) }
                }
            } else if let text = scalarString(value) {
                result.append(text)
            }
        }
        return result
    }

    /// Danh sách phần tử để duyệt (bookList / chapterList). Mảng lồng được mở một cấp.
    public static func list(_ path: String, on root: Any) -> [Any] {
        let values = evaluate(path, on: root)
        if values.count == 1, let single = values.first as? [Any] {
            return single
        }
        return values
    }

    private static func scalarString(_ value: Any) -> String? {
        if value is NSNull { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber { return LegadoJSON.string(number) }
        if value is [Any] || value is [String: Any] {
            return LegadoJSON.encode(value)
        }
        return nil
    }

    // MARK: - Token

    private enum Token {
        case key(String)
        case recursiveKey(String)
        case wildcard
        case indexes([Int])
        case slice(start: Int?, end: Int?)
        case filter(field: String, operatorSymbol: String, value: String)
        case length
    }

    private static func tokenize(_ expression: String) -> [Token] {
        var tokens: [Token] = []
        let chars = Array(expression)
        var index = 0

        func readIdentifier() -> String {
            var text = ""
            while index < chars.count {
                let char = chars[index]
                if char == "." || char == "[" { break }
                text.append(char)
                index += 1
            }
            return text
        }

        while index < chars.count {
            let char = chars[index]

            if char == "." {
                index += 1
                if index < chars.count, chars[index] == "." {
                    index += 1
                    let name = readIdentifier()
                    if !name.isEmpty { tokens.append(.recursiveKey(name)) }
                    continue
                }
                let name = readIdentifier()
                if name == "*" {
                    tokens.append(.wildcard)
                } else if name.hasSuffix("()") {
                    if name == "length()" { tokens.append(.length) }
                } else if !name.isEmpty {
                    tokens.append(.key(name))
                }
                continue
            }

            if char == "[" {
                guard let closeOffset = chars[index...].firstIndex(of: "]") else { break }
                let body = String(chars[(index + 1)..<closeOffset])
                index = closeOffset + 1
                if let token = parseBracket(body) { tokens.append(token) }
                continue
            }

            // Khoá đứng ngay đầu chuỗi khi rule viết `content.list` thay vì `$.content.list`.
            let name = readIdentifier()
            if name.isEmpty {
                index += 1
            } else {
                tokens.append(.key(name))
            }
        }
        return tokens
    }

    private static func parseBracket(_ body: String) -> Token? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == "*" { return .wildcard }

        if trimmed.hasPrefix("?") {
            return parseFilter(trimmed)
        }

        // `['a']` hoặc `["a"]`
        if let first = trimmed.first, first == "'" || first == "\"" {
            let name = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return name.isEmpty ? nil : .key(name)
        }

        if trimmed.contains(":") {
            let parts = trimmed.components(separatedBy: ":")
            let start = Int(parts[0].trimmingCharacters(in: .whitespaces))
            let end = parts.count > 1 ? Int(parts[1].trimmingCharacters(in: .whitespaces)) : nil
            return .slice(start: start, end: end)
        }

        let numbers = trimmed.components(separatedBy: ",").compactMap {
            Int($0.trimmingCharacters(in: .whitespaces))
        }
        if !numbers.isEmpty { return .indexes(numbers) }

        // `[key]` không nháy — vẫn gặp trong nguồn viết tay.
        return .key(trimmed)
    }

    private static func parseFilter(_ body: String) -> Token? {
        // Dạng `?(@.field == 'value')`
        var inner = body
        if let open = inner.firstIndex(of: "("), let close = inner.lastIndex(of: ")") {
            inner = String(inner[inner.index(after: open)..<close])
        }
        inner = inner.trimmingCharacters(in: .whitespacesAndNewlines)
        guard inner.hasPrefix("@") else { return nil }

        for symbol in ["=~", "==", "!=", ">=", "<=", ">", "<"] {
            guard let range = inner.range(of: symbol) else { continue }
            var field = String(inner[inner.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            field = field.replacingOccurrences(of: "@.", with: "")
            field = field.replacingOccurrences(of: "@", with: "")
            var value = String(inner[range.upperBound...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
            return .filter(field: field, operatorSymbol: symbol, value: value)
        }
        return nil
    }

    // MARK: - Duyệt

    private static func walk(tokens: [Token], values: [Any]) -> [Any] {
        var current = values
        for token in tokens {
            var next: [Any] = []
            switch token {
            case .key(let name):
                for value in current {
                    if let dict = value as? [String: Any], let found = dict[name] {
                        next.append(found)
                    } else if let list = value as? [Any] {
                        // JSONPath chuẩn cho phép bỏ qua một cấp mảng khi lấy khoá.
                        for item in list {
                            if let dict = item as? [String: Any], let found = dict[name] {
                                next.append(found)
                            }
                        }
                    }
                }

            case .recursiveKey(let name):
                for value in current {
                    collectRecursive(name, in: value, into: &next)
                }

            case .wildcard:
                for value in current {
                    if let list = value as? [Any] {
                        next.append(contentsOf: list)
                    } else if let dict = value as? [String: Any] {
                        next.append(contentsOf: dict.values)
                    }
                }

            case .indexes(let positions):
                for value in current {
                    guard let list = value as? [Any] else { continue }
                    for position in positions {
                        let resolved = position < 0 ? position + list.count : position
                        if resolved >= 0, resolved < list.count {
                            next.append(list[resolved])
                        }
                    }
                }

            case .slice(let start, let end):
                for value in current {
                    guard let list = value as? [Any] else { continue }
                    var lower = start ?? 0
                    if lower < 0 { lower += list.count }
                    var upper = end ?? list.count
                    if upper < 0 { upper += list.count }
                    lower = max(0, min(lower, list.count))
                    upper = max(lower, min(upper, list.count))
                    next.append(contentsOf: list[lower..<upper])
                }

            case .filter(let field, let symbol, let expected):
                for value in current {
                    let candidates = (value as? [Any]) ?? [value]
                    for item in candidates {
                        guard let dict = item as? [String: Any] else { continue }
                        if matches(dict[field], symbol: symbol, expected: expected) {
                            next.append(item)
                        }
                    }
                }

            case .length:
                for value in current {
                    if let list = value as? [Any] {
                        next.append(NSNumber(value: list.count))
                    } else if let dict = value as? [String: Any] {
                        next.append(NSNumber(value: dict.count))
                    } else if let text = value as? String {
                        next.append(NSNumber(value: text.count))
                    }
                }
            }
            current = next
            if current.isEmpty { break }
        }
        return current
    }

    private static func collectRecursive(_ name: String, in value: Any, into output: inout [Any]) {
        if let dict = value as? [String: Any] {
            if let found = dict[name] { output.append(found) }
            for nested in dict.values {
                collectRecursive(name, in: nested, into: &output)
            }
        } else if let list = value as? [Any] {
            for item in list {
                collectRecursive(name, in: item, into: &output)
            }
        }
    }

    private static func matches(_ raw: Any?, symbol: String, expected: String) -> Bool {
        guard let raw, !(raw is NSNull) else { return false }
        let actual = scalarString(raw) ?? ""

        if symbol == "=~" {
            return actual.range(of: expected, options: .regularExpression) != nil
        }
        if let actualNumber = Double(actual), let expectedNumber = Double(expected) {
            switch symbol {
            case "==": return actualNumber == expectedNumber
            case "!=": return actualNumber != expectedNumber
            case ">": return actualNumber > expectedNumber
            case "<": return actualNumber < expectedNumber
            case ">=": return actualNumber >= expectedNumber
            case "<=": return actualNumber <= expectedNumber
            default: return false
            }
        }
        switch symbol {
        case "==": return actual == expected
        case "!=": return actual != expected
        case ">": return actual > expected
        case "<": return actual < expected
        case ">=": return actual >= expected
        case "<=": return actual <= expected
        default: return false
        }
    }



}
