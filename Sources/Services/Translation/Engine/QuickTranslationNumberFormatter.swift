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
    ///
    /// Trước khi coi chuỗi là **một** số, kiểm tra dạng **nhiều số viết dính nhau** — xem
    /// `enumeratedNumbers`. Tiếng Trung không bao giờ viết 23 là `二三` (phải là `二十三`), nên chữ số
    /// Hán trần đứng liền nhau là các số riêng, không phải một số ghép.
    public static func renderNumeral(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ ($0.isASCII || "０１２３４５６７８９".contains($0)) && $0.isNumber }) {
            return normalizeFullWidth(value)
        }
        if let numbers = enumeratedNumbers(value) {
            return numbers.map(String.init).joined(separator: ", ")
        }
        if !value.contains(where: { smallMagnitudes[$0] != nil || largeMagnitudes[$0] != nil }) {
            return renderDigitwise(value)
        }
        guard let parsed = parseChineseNumeral(value) else { return value }
        return String(parsed)
    }

    /// Chỉ chữ số Hán **trần** — không gồm bậc `十百千万…`, không gồm `0-9` ASCII/full-width.
    private static let bareHanDigits: Set<Character> = Set("〇零一二两兩三四五六七八九")

    /// Nhận dạng **nhiều số viết dính nhau** và trả về từng số.
    ///
    /// Điều kiện: chuỗi có đúng **một** dãy gồm **từ hai** chữ số Hán trần liền nhau, và các chữ số đó
    /// tăng liền bậc (`d`, `d+1`, `d+2`…). Giá trị từng số tính bằng cách thay cả dãy đó lần lượt bằng
    /// **một** chữ số rồi đọc chuỗi như một số thường — nhờ vậy bậc đứng trước hay sau đều đúng:
    ///
    /// * `二三` → 2, 3            (không có bậc)
    /// * `一二三` → 1, 2, 3
    /// * `十三四` → 13, 14        (bậc đứng trước: 十三四岁 = 13, 14 tuổi)
    /// * `三十四五` → 34, 35
    /// * `二三十` → 20, 30        (bậc đứng sau)
    /// * `三四百` → 300, 400
    /// * `三百四五十` → 340, 350  (bậc cả hai phía)
    ///
    /// Trả `nil` — tức đọc như **một** số — cho mọi trường hợp còn lại. Ba cửa hẹp:
    /// * Chỉ **một** dãy. `二三四五六七` kiểu mã số nhiều đoạn không rơi vào đây vì vẫn là một dãy, nhưng
    ///   chuỗi có hai dãy rời (`二三十四五`) thì bỏ, vì không biết ghép theo cụm nào.
    /// * **Không** chứa `零`/`〇`: `二零二五` là năm đọc theo từng chữ số (2025), không phải liệt kê.
    /// * Phải tăng **đúng một** mỗi bước: `五三七` là mã số nên giữ `537`, và `三百二十` không có dãy nào
    ///   dài ≥ 2 nên vẫn ra đúng `320`.
    private static func enumeratedNumbers(_ value: String) -> [Int]? {
        let chars = Array(value)
        guard chars.count >= 2 else { return nil }
        guard !chars.contains("零"), !chars.contains("〇") else { return nil }

        var runStart: Int? = nil
        var runLength = 0
        var index = 0
        while index < chars.count {
            guard bareHanDigits.contains(chars[index]) else {
                index += 1
                continue
            }
            var end = index
            while end < chars.count, bareHanDigits.contains(chars[end]) {
                end += 1
            }
            let length = end - index
            if length >= 2 {
                // Dãy thứ hai ⇒ không biết ghép bậc theo cụm nào, bỏ cả chuỗi.
                if runStart != nil { return nil }
                runStart = index
                runLength = length
            }
            index = end
        }

        guard let start = runStart else { return nil }

        var digits: [Int] = []
        for offset in 0..<runLength {
            guard let digit = digitMap[chars[start + offset]] else { return nil }
            if let last = digits.last, digit != last + 1 { return nil }
            digits.append(digit)
        }

        let prefix = String(chars[0..<start])
        let suffix = String(chars[(start + runLength)...])
        var numbers: [Int] = []
        for char in chars[start..<(start + runLength)] {
            guard let parsed = parseChineseNumeral(prefix + String(char) + suffix) else { return nil }
            if let last = numbers.last, parsed <= last { return nil }
            numbers.append(parsed)
        }
        return numbers
    }

    /// Đọc một chuỗi số Hán thành `Int`; `nil` khi tràn. Cộng dồn theo *section* nên `一万亿` ra
    /// `100010000` — giữ nguyên theo reference `ruleEngine.ts`.
    private static func parseChineseNumeral(_ value: String) -> Int? {
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
            if overflow { return nil }
        }

        let result = add(add(total, section), current)
        return overflow ? nil : result
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
