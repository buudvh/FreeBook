import Foundation

/// Lớp ký tự và cách render của các token số: `<n>`, `<y>`, `<h>`, `<d>`, `<L>`.
///
/// Hai điểm **cố ý lệch** reference (`ruleEngine.ts`), làm theo header đặc tả trong file rule:
/// 1. `<y>` **không** nhận ký tự bậc `十百千万萬亿億兆` — reference dùng chung lớp ký tự với `<n>`
///    rồi map từng ký tự, nên `十` bị giữ nguyên và làm hỏng nhóm rule `十<y:1>级 = cấp 1{0}`.
/// 2. `<L>` cố định đúng một ký tự (xem `QuickTranslationRuleParser`).
///
/// Giữ nguyên theo reference: `chineseNumber` cộng dồn theo *section* nên `一万亿` ra `100010000`,
/// và **không** tự thêm dấu phân cách số (`1000000`, không phải `1.000.000`).
public enum QuickTranslationNumberFormatter {
    /// `<n>`: chuỗi số Hán hoặc Ả Rập, kể cả ký tự bậc + full-width digits.
    public static let numeralUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九十百千万萬亿億兆0123456789０１２３４５６７８９")
    /// `<y>`: đọc từng chữ số, không nhận ký tự bậc. Nhận chữ số Hán + ASCII + full-width.
    public static let digitwiseUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九0123456789０１２３４５６７８９")
    /// `<h>`: chỉ chữ số Hán `〇零一二两兩三四五六七八九`; không nhận bậc, không nhận 0-9.
    public static let hanDigitsUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九")
    /// `<d>`: chỉ digit 0-9 (ASCII `0123456789` + full-width `０１２３４５６７８９`).
    public static let asciiDigitsUnits: Set<UInt16> = makeUnits("0123456789０１２３４５６７８９")
    /// `<L>`: nhãn chương.
    public static let chapterLabelUnits: Set<UInt16> = makeUnits("章卷集节節幕回折")

    private static let digitMap: [Character: Int] = [
        "〇": 0, "零": 0, "一": 1, "二": 2, "两": 2, "兩": 2,
        "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9,
        "0": 0, "1": 1, "2": 2, "3": 3, "4": 4, "5": 5, "6": 6, "7": 7, "8": 8, "9": 9,
        "０": 0, "１": 1, "２": 2, "３": 3, "４": 4, "５": 5, "６": 6, "７": 7, "８": 8, "９": 9
    ]

    private static let smallMagnitudes: [Character: Int] = ["十": 10, "百": 100, "千": 1000]
    private static let largeMagnitudes: [Character: Int] = [
        "万": 10_000, "萬": 10_000, "亿": 100_000_000, "億": 100_000_000, "兆": 1_000_000_000_000
    ]

    private static let chapterLabels: [Character: String] = [
        "章": "Chương", "卷": "Quyển", "集": "Tập", "节": "Tiết",
        "節": "Tiết", "幕": "Màn", "回": "Hồi", "折": "Chiết"
    ]

    /// Tập ký tự hợp lệ của một token số, dùng cho cả matcher và boundary guard.
    public static func units(for kind: QuickTranslationRuleElement.NumeralKind) -> Set<UInt16> {
        switch kind {
        case .chinese: return numeralUnits
        case .digitwise: return digitwiseUnits
        case .hanDigits: return hanDigitsUnits
        case .asciiDigits: return asciiDigitsUnits
        }
    }

    // MARK: - Render

    /// `<n>`: số Hán → số Ả Rập. Chuỗi toàn chữ số ASCII/full-width được trả nguyên văn (giữ cả `0` dẫn đầu).
    public static func renderNumeral(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ ($0.isASCII || "０１２３４５６７８９".contains($0)) && $0.isNumber }) {
            return normalizeFullWidth(value)
        }
        if !value.contains(where: { smallMagnitudes[$0] != nil || largeMagnitudes[$0] != nil }) {
            return renderDigitwise(value)
        }

        var total = 0
        var section = 0
        var current = 0
        var overflow = false

        func multiply(_ lhs: Int, _ rhs: Int) -> Int {
            let (result, didOverflow) = lhs.multipliedReportingOverflow(by: rhs)
            if didOverflow { overflow = true; return 0 }
            return result
        }

        func add(_ lhs: Int, _ rhs: Int) -> Int {
            let (result, didOverflow) = lhs.addingReportingOverflow(rhs)
            if didOverflow { overflow = true; return 0 }
            return result
        }

        for char in value {
            if let small = smallMagnitudes[char] {
                if current == 0 { current = 1 }
                section = add(section, multiply(current, small))
                current = 0
            } else if let large = largeMagnitudes[char] {
                section = add(section, current)
                if section == 0 { section = 1 }
                total = add(total, multiply(section, large))
                section = 0
                current = 0
            } else {
                current = add(multiply(current, 10), digitMap[char] ?? 0)
            }
            if overflow { return value }
        }

        let result = add(add(total, section), current)
        return overflow ? value : String(result)
    }

    /// `<y>`: đọc từng chữ số. Ký tự không phải chữ số được giữ nguyên (như reference).
    /// Nhận chữ số Hán + ASCII + full-width.
    public static func renderDigitwise(_ value: String) -> String {
        var output = ""
        for char in value {
            if let digit = digitMap[char] {
                output += String(digit)
            } else {
                output.append(char)
            }
        }
        return output
    }

    /// `<h>`: chỉ chữ số Hán, đọc từng chữ số thành 0-9. Không nhận bậc, không nhận 0-9.
    public static func renderHanDigits(_ value: String) -> String {
        var output = ""
        for char in value {
            if let digit = digitMap[char] {
                output += String(digit)
            } else {
                output.append(char)
            }
        }
        return output
    }

    /// `<d>`: chỉ digit 0-9 (ASCII + full-width), render full-width về ASCII.
    public static func renderAsciiDigits(_ value: String) -> String {
        var output = ""
        for char in value {
            if let digit = digitMap[char] {
                output += String(digit)
            } else {
                output.append(char)
            }
        }
        return output
    }

    /// `<L>`: sinh tên nhãn tiếng Việt.
    public static func renderChapterLabel(_ value: String) -> String {
        guard let char = value.first, value.count == 1 else { return value }
        return chapterLabels[char] ?? value
    }

    private static func normalizeFullWidth(_ value: String) -> String {
        var output = ""
        for char in value {
            if let digit = digitMap[char] {
                output += String(digit)
            } else {
                output.append(char)
            }
        }
        return output
    }

    private static func makeUnits(_ characters: String) -> Set<UInt16> {
        Set(characters.utf16)
    }
}
