import Foundation

/// Bộ cắt chuỗi rule của Legado — port `RuleAnalyzer.kt`.
///
/// Không thể dùng `split(separator:)` thô: dấu `@`, `&&`, `||` xuất hiện **bên trong** selector
/// (`[href="a@b"]`, `:contains(a&&b)`) và bên trong biểu thức `{{…}}`. Legado giải quyết bằng cách bỏ
/// qua dấu phân cách nằm trong nhóm ngoặc cân bằng và trong nháy (`chompRuleBalanced`, `:127-160`).
/// Bản này giữ đúng hành vi đó bằng một lượt quét, thêm theo dõi `{}` cho khối `{{…}}`.
public enum LegadoRuleLexer {

    /// Cắt theo **một** dấu phân cách.
    public static func split(_ input: String, separator: String) -> [String] {
        guard !separator.isEmpty, !input.isEmpty else { return [input] }
        var parts: [String] = []
        var current = String.UnicodeScalarView()
        var scanner = BalanceScanner()
        let scalars = Array(input.unicodeScalars)
        let sep = Array(separator.unicodeScalars)
        var index = 0

        while index < scalars.count {
            let scalar = scalars[index]
            if scanner.isAtTopLevel, matches(scalars, at: index, pattern: sep) {
                parts.append(String(String.UnicodeScalarView(current)))
                current = String.UnicodeScalarView()
                index += sep.count
                continue
            }
            scanner.consume(scalar)
            if scanner.skipNextScalar {
                current.append(scalar)
                index += 1
                if index < scalars.count {
                    current.append(scalars[index])
                    index += 1
                }
                scanner.skipNextScalar = false
                continue
            }
            current.append(scalar)
            index += 1
        }
        parts.append(String(String.UnicodeScalarView(current)))
        return parts
    }

    /// Tìm dấu phân cách **xuất hiện đầu tiên** trong danh sách rồi cắt theo dấu đó.
    ///
    /// Giống `splitRule(vararg split:)`: `elementsType` là dấu tìm được, và chỉ dấu đó được dùng để
    /// cắt. Trả `nil` ở `separator` khi không tìm thấy dấu nào (chuỗi là một phần tử duy nhất).
    public static func split(
        _ input: String,
        separators: [String]
    ) -> (parts: [String], separator: String?) {
        guard let found = firstSeparator(in: input, candidates: separators) else {
            return ([input], nil)
        }
        return (split(input, separator: found), found)
    }

    /// Bỏ `@` và khoảng trắng ở đầu chuỗi (`RuleAnalyzer.trim`, `:13-21`).
    public static func trimLeading(_ input: String) -> String {
        var result = Substring(input)
        while let first = result.first, first == "@" || first.isWhitespace {
            result = result.dropFirst()
        }
        return String(result)
    }

    /// Vị trí dấu phân cách đầu tiên ở mức ngoài cùng, hoặc `nil`.
    public static func firstSeparator(in input: String, candidates: [String]) -> String? {
        let scalars = Array(input.unicodeScalars)
        let patterns = candidates.map { Array($0.unicodeScalars) }
        var scanner = BalanceScanner()
        var index = 0
        while index < scalars.count {
            if scanner.isAtTopLevel {
                for (offset, pattern) in patterns.enumerated() {
                    if matches(scalars, at: index, pattern: pattern) {
                        return candidates[offset]
                    }
                }
            }
            scanner.consume(scalars[index])
            if scanner.skipNextScalar {
                scanner.skipNextScalar = false
                index += 2
                continue
            }
            index += 1
        }
        return nil
    }

    /// Thay mọi khối `open…close` **từ trong ra ngoài** bằng kết quả của `transform`.
    ///
    /// Dùng cho `{{ }}`: nguồn thật có khối lồng nhau (`"…{{ … {{x}} … }}"`), nên phải khớp cặp
    /// trong cùng trước — tìm `close` đầu tiên rồi lùi về `open` gần nhất.
    public static func expandInner(
        _ input: String,
        open: String = "{{",
        close: String = "}}",
        limit: Int = 64,
        transform: (String) -> String
    ) -> String {
        var result = input
        var rounds = 0
        while rounds < limit {
            rounds += 1
            guard let closeRange = result.range(of: close) else { break }
            let head = result[result.startIndex..<closeRange.lowerBound]
            guard let openRange = head.range(of: open, options: .backwards) else { break }
            let inner = String(result[openRange.upperBound..<closeRange.lowerBound])
            let replacement = transform(inner)
            result.replaceSubrange(openRange.lowerBound..<closeRange.upperBound, with: replacement)
        }
        return result
    }

    private static func matches(
        _ scalars: [Unicode.Scalar],
        at index: Int,
        pattern: [Unicode.Scalar]
    ) -> Bool {
        guard !pattern.isEmpty, index + pattern.count <= scalars.count else { return false }
        for offset in 0..<pattern.count where scalars[index + offset] != pattern[offset] {
            return false
        }
        return true
    }
}
