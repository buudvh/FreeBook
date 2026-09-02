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
    /// Trước khi coi chuỗi là **một** số, kiểm tra dạng khoảng xấp xỉ (`四五` = "4 đến 5") — xem
    /// `approximateRange`. Tiếng Trung không bao giờ viết 45 là `四五` (phải là `四十五`), nên hai chữ
    /// số Hán trần đứng liền nhau luôn là idiom "từ mấy đến mấy", không phải số ghép.
    public static func renderNumeral(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ ($0.isASCII || "０１２３４５６７８９".contains($0)) && $0.isNumber }) {
            return normalizeFullWidth(value)
        }
        if let range = approximateRange(value) {
            return "\(range.low) đến \(range.high)"
        }
        if let list = enumeratedDigits(value) {
            return list
        }
        if !value.contains(where: { smallMagnitudes[$0] != nil || largeMagnitudes[$0] != nil }) {
            return renderDigitwise(value)
        }
        guard let parsed = parseChineseNumeral(value) else { return value }
        return String(parsed)
    }

    /// Chỉ chữ số Hán **trần** — không gồm bậc `十百千万…`, không gồm `0-9` ASCII/full-width.
    private static let bareHanDigits: Set<Character> = Set("〇零一二两兩三四五六七八九")

    /// Dãy **ba chữ số Hán trần trở lên, tăng liền bậc** ⇒ một **danh sách** số, không phải một số ghép.
    ///
    /// Cùng tiền đề với `approximateRange`: tiếng Trung không viết 123 là `一二三` (phải là
    /// `一百二十三`), nên chuỗi đó là các số viết dính nhau. Với **hai** chữ số nó là idiom khoảng
    /// ("四五" = 4 đến 5, xử lý ở `approximateRange`); từ **ba** chữ số trở lên nó là liệt kê:
    /// `一二三级` → `1, 2, 3 cấp`.
    ///
    /// Ba cửa hẹp giữ hành vi cũ cho mọi thứ khác:
    /// * Toàn chuỗi phải là chữ số Hán trần — có bậc (`一百二十三`) hay digit ASCII thì đi đường cũ.
    /// * **Không** chứa `零`/`〇` — `二零二五` là năm đọc theo từng chữ số, không phải liệt kê.
    /// * Phải tăng **đúng một** mỗi bước — `五三七` là mã số, giữ nguyên `537`.
    private static func enumeratedDigits(_ value: String) -> String? {
        let chars = Array(value)
        guard chars.count >= 3, chars.allSatisfy({ bareHanDigits.contains($0) }) else { return nil }
        guard !chars.contains("零"), !chars.contains("〇") else { return nil }

        var digits: [Int] = []
        for char in chars {
            guard let digit = digitMap[char] else { return nil }
            if let last = digits.last, digit != last + 1 { return nil }
            digits.append(digit)
        }
        return digits.map(String.init).joined(separator: ", ")
    }

    /// Nhận dạng khoảng xấp xỉ kiểu Hán: đúng **một** dãy gồm **đúng hai** chữ số Hán trần liền nhau
    /// và hai chữ số đó tăng liền bậc (`d`, `d+1`). Giá trị hai đầu tính bằng cách thay dãy đó lần lượt
    /// bằng từng chữ số rồi đọc như một số thường, nên mọi vị trí của dãy đều đúng:
    ///
    /// * `四五` → 4 … 5        (dãy ở giữa chuỗi rỗng)
    /// * `十七八` → 17 … 18    (dãy ở cuối, có bậc phía trước)
    /// * `三十四五` → 34 … 35
    /// * `二三十` → 20 … 30    (dãy ở đầu, có bậc phía sau)
    /// * `三四百` → 300 … 400
    ///
    /// Trả `nil` cho mọi thứ khác — đặc biệt là dãy dài hơn hai (`二零二五` = 2025 đọc từng chữ số) và
    /// dãy không tăng liền bậc (`零五`, `一〇`) — để hành vi cũ giữ nguyên.
    private static func approximateRange(_ value: String) -> (low: Int, high: Int)? {
        let chars = Array(value)
        guard chars.count >= 2 else { return nil }

        var runStart: Int? = nil
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
                // Dãy thứ hai, hoặc dãy dài hơn 2 ⇒ không phải idiom khoảng: bỏ qua cả chuỗi.
                if runStart != nil || length != 2 { return nil }
                runStart = index
            }
            index = end
        }

        guard let start = runStart,
              let first = digitMap[chars[start]],
              let second = digitMap[chars[start + 1]],
              second == first + 1 else { return nil }

        let prefix = String(chars[0..<start])
        let suffix = String(chars[(start + 2)...])
        guard let low = parseChineseNumeral(prefix + String(chars[start]) + suffix),
              let high = parseChineseNumeral(prefix + String(chars[start + 1]) + suffix),
              low < high else { return nil }
        return (low, high)
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
