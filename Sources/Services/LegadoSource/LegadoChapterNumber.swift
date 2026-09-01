import Foundation

/// Đổi số Hán trong tên chương thành số Ả Rập — `java.toNumChapter`.
///
/// Không dùng lại `TranslateUtils.translateChapterTitle`: hàm đó dịch **cả** tên chương sang tiếng
/// Việt (`第一章` → `Chương 1`), còn ở đây nguồn chỉ muốn đổi chữ số và **giữ nguyên tiếng Trung**
/// (`第一章` → `第1章`), vì kết quả còn đi qua tầng dịch của app sau đó.
public enum LegadoChapterNumber {

    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "壹": 1, "贰": 2, "叁": 3, "肆": 4, "伍": 5,
        "陆": 6, "柒": 7, "捌": 8, "玖": 9
    ]

    private static let units: [Character: Int] = [
        "十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000
    ]

    public static func normalize(_ title: String) -> String {
        let pattern = "第\\s*([零〇一二两三四五六七八九十百千壹贰叁肆伍陆柒捌玖拾佰仟]+)\\s*([章节回卷集部篇话幕折])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return title }

        let text = title as NSString
        var result = title
        let matches = regex.matches(
            in: title,
            options: [],
            range: NSRange(location: 0, length: text.length)
        )
        for match in matches.reversed() {
            guard match.numberOfRanges > 2 else { continue }
            let numberText = text.substring(with: match.range(at: 1))
            let unit = text.substring(with: match.range(at: 2))
            let value = parse(numberText)
            guard value > 0 else { continue }
            let whole = text.substring(with: match.range)
            guard let range = result.range(of: whole) else { continue }
            result.replaceSubrange(range, with: "第\(value)\(unit)")
        }
        return result
    }

    /// Số Hán → Int. Hỗ trợ tới đơn vị 万.
    public static func parse(_ raw: String) -> Int {
        if let direct = Int(raw) { return direct }
        var total = 0
        var current = 0
        var hasValue = false

        for character in raw {
            if let digit = digits[character] {
                current = digit
                hasValue = true
                continue
            }
            if let unit = units[character] {
                if current == 0 { current = 1 }
                total += current * unit
                current = 0
                hasValue = true
                continue
            }
            if character == "万" {
                total = (total + current) * 10000
                current = 0
                hasValue = true
                continue
            }
        }
        guard hasValue else { return 0 }
        return total + current
    }
}
