import Foundation

/// `java.toNumChapter` (spec §6.4.2, U10): đổi số Hán trong `第…章/节/回/卷/集/部/篇` sang số Ả Rập;
/// không khớp ⇒ trả nguyên chuỗi.
enum LegadoChineseNumber {
    private static let pattern = try? NSRegularExpression(
        pattern: "第([零〇一二两三四五六七八九十百千万亿壹贰叁肆伍陆柒捌玖拾佰仟]+)([章节節回卷集部篇])"
    )

    private static let digits: [Character: Int] = [
        "零": 0, "〇": 0, "一": 1, "壹": 1, "二": 2, "两": 2, "贰": 2, "三": 3, "叁": 3, "四": 4, "肆": 4,
        "五": 5, "伍": 5, "六": 6, "陆": 6, "七": 7, "柒": 7, "八": 8, "捌": 8, "九": 9, "玖": 9
    ]
    private static let units: [Character: Int] = ["十": 10, "拾": 10, "百": 100, "佰": 100, "千": 1000, "仟": 1000]

    static func toNumChapter(_ text: String) -> String {
        guard let regex = pattern else { return text }
        let nsText = text as NSString
        var output = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            output += nsText.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let numeral = nsText.substring(with: match.range(at: 1))
            let unit = nsText.substring(with: match.range(at: 2))
            if let value = parse(numeral) {
                output += "第\(value)\(unit)"
            } else {
                output += nsText.substring(with: match.range)
            }
            cursor = match.range.location + match.range.length
        }
        output += nsText.substring(from: cursor)
        return output
    }

    /// Số Hán → số nguyên. Không có đơn vị (`一二三`) ⇒ ghép từng chữ số.
    static func parse(_ numeral: String) -> Int? {
        let characters = Array(numeral)
        guard !characters.isEmpty else { return nil }
        if !characters.contains(where: { units[$0] != nil || $0 == "万" || $0 == "亿" }) {
            var joined = 0
            for character in characters {
                guard let digit = digits[character] else { return nil }
                joined = joined * 10 + digit
                if joined > 1_000_000_000 { return nil }
            }
            return joined
        }
        var total = 0
        var section = 0
        var number = 0
        for character in characters {
            if let digit = digits[character] {
                number = digit
            } else if let unit = units[character] {
                if number == 0 && (unit == 10 || (section == 0 && total == 0)) { number = 1 }
                section += number * unit
                number = 0
            } else if character == "万" {
                section = (section + number) * 10_000
                total += section
                section = 0
                number = 0
            } else if character == "亿" {
                guard total + section + number < 100_000 else { return nil }
                total = (total + section + number) * 100_000_000
                section = 0
                number = 0
            } else {
                return nil
            }
            if total > 1_000_000_000_000 || section > 1_000_000_000_000 { return nil }
        }
        return total + section + number
    }
}
