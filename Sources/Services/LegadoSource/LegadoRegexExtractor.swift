import Foundation

/// Chế độ `Regex` — port `AnalyzeByRegex.kt`.
///
/// Rule regex của Legado là **danh sách** biểu thức ngăn bằng `&&`: mọi biểu thức trừ cái cuối dùng để
/// **thu hẹp** chuỗi (nối mọi lần khớp lại), biểu thức cuối tạo ra các "phần tử" mà mỗi phần tử là
/// danh sách nhóm bắt (`group(0)` ở chỉ số 0).
///
/// Trong rule con của một phần tử, `$1`, `$2`… tham chiếu nhóm bắt tương ứng.
public enum LegadoRegexExtractor {

    private static let cache = LegadoRuleCache<NSRegularExpression>(limit: 128)

    public static func regex(_ pattern: String) -> NSRegularExpression? {
        if let cached = cache.value(for: pattern) { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        cache.set(compiled, for: pattern)
        return compiled
    }

    /// Nhiều phần tử, mỗi phần tử là mảng nhóm bắt.
    public static func elements(in source: String, patterns: [String]) -> [[String]] {
        guard let first = patterns.first else { return [] }
        guard let expression = regex(first) else { return [] }

        let text = source as NSString
        let matches = expression.matches(
            in: source,
            options: [],
            range: NSRange(location: 0, length: text.length)
        )
        guard !matches.isEmpty else { return [] }

        if patterns.count == 1 {
            return matches.map { match in
                (0..<match.numberOfRanges).map { groupIndex in
                    let range = match.range(at: groupIndex)
                    return range.location == NSNotFound ? "" : text.substring(with: range)
                }
            }
        }

        let narrowed = matches.map { text.substring(with: $0.range) }.joined()
        return elements(in: narrowed, patterns: Array(patterns.dropFirst()))
    }

    /// Một phần tử (mảng nhóm bắt của lần khớp đầu).
    public static func element(in source: String, patterns: [String]) -> [String]? {
        elements(in: source, patterns: patterns).first
    }

    /// Áp `##regex##replacement` lên kết quả — port `AnalyzeRule.replaceRegex` (`:524-548`).
    ///
    /// Hai nhánh có ngữ nghĩa **rất khác**: chế độ "thay lần đầu" chỉ trả về *đúng đoạn khớp đầu tiên*
    /// sau khi thay, và trả **chuỗi rỗng** khi không khớp — không phải trả nguyên bản.
    public static func applyReplacement(
        to result: String,
        pattern: String,
        replacement: String,
        firstOnly: Bool
    ) -> String {
        guard !pattern.isEmpty else { return result }
        guard let expression = regex(pattern) else {
            // Regex không hợp lệ: Legado rơi về thay thế chuỗi thuần.
            return result.replacingOccurrences(of: pattern, with: replacement)
        }
        let text = result as NSString
        let fullRange = NSRange(location: 0, length: text.length)

        if firstOnly {
            guard let match = expression.firstMatch(in: result, options: [], range: fullRange) else {
                return ""
            }
            let matched = text.substring(with: match.range)
            let matchedText = matched as NSString
            return expression.stringByReplacingMatches(
                in: matched,
                options: [],
                range: NSRange(location: 0, length: matchedText.length),
                withTemplate: replacement
            )
        }

        return expression.stringByReplacingMatches(
            in: result,
            options: [],
            range: fullRange,
            withTemplate: replacement
        )
    }

    /// Thay `$1`, `$2`… trong rule con bằng nhóm bắt của phần tử regex.
    public static func substituteGroups(_ rule: String, groups: [String]) -> String {
        guard !groups.isEmpty else { return rule }
        var result = rule
        // Thay từ nhóm lớn về nhóm nhỏ để `$10` không bị `$1` ăn trước.
        for index in stride(from: groups.count - 1, through: 0, by: -1) {
            result = result.replacingOccurrences(of: "$\(index)", with: groups[index])
        }
        return result
    }
}
