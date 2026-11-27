import Foundation

/// Lớp ký tự và cách render của các token số: `<n>`, `<y>`, `<h>`, `<d>`, `<L>`.
///
/// Hai điểm **cố ý lệch** reference (`ruleEngine.ts`), làm theo header đặc tả trong file rule:
/// 1. `<y>` **không** nhận ký tự bậc `十百千万萬亿億兆` — reference dùng chung lớp ký tự với `<n>`
///    rồi map từng ký tự, nên `十` bị giữ nguyên và làm hỏng nhóm rule `十<y:1>级 = cấp 1{0}`.
/// 2. `<L>` cố định đúng một ký tự (xem `QuickTranslationRuleParser`).
///
/// **Lệch** reference từ 1.3.1093: bậc lớn **nhân** vế trái thay vì cộng dồn theo *section* — `一万亿` ra
/// `1000000000000`, `两万万` ra `200000000` (reference ra `100010000` và `30000`). Vẫn **không** tự thêm dấu phân cách
/// số (`1000000`, không phải `1.000.000`).
public enum QuickTranslationNumberFormatter {
    /// `<n>`: chuỗi số Hán hoặc Ả Rập, kể cả ký tự bậc + full-width digits.
    public static let numeralUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九十百千万萬亿億兆0123456789０１２３４５６７８９")
    /// `<y>`: đọc từng chữ số, không nhận ký tự bậc. Nhận chữ số Hán + ASCII + full-width.
    public static let digitwiseUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九0123456789０１２３４５６７８９")
    /// `<h>`: chỉ chữ số Hán `〇零一二两兩三四五六七八九`; không nhận bậc, không nhận 0-9.
    public static let hanDigitsUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九")
    /// `<hn>`: số Hán đầy đủ — chữ số Hán **và** ký tự bậc. Khác `<n>` đúng ở chỗ không nhận
    /// `0-9`/`０-９`, nên `<hn>` là **lớp con thật** của `<n>`; khác `<h>` ở chỗ nuốt được `十百千万`.
    public static let hanNumeralUnits: Set<UInt16> = makeUnits("〇零一二两兩三四五六七八九十百千万萬亿億兆")
    /// `<d>`: chỉ digit 0-9 (ASCII `0123456789` + full-width `０１２３４５６７８９`).
    public static let asciiDigitsUnits: Set<UInt16> = makeUnits("0123456789０１２３４５６７８９")
    /// `<m>`: token cơ số 10 (mươi, trăm, nghìn, hai mươi, chục vạn...).
    public static var magnitudeUnits: Set<UInt16> { QuickTranslationMagnitudeFormatter.magnitudeUnits }
    /// `<a>`: chữ cái Latin cơ bản, cả hoa và thường, **kể cả full-width** `Ａ-Ｚ`/`ａ-ｚ` vì văn bản
    /// Trung hay viết cấp bậc bằng ký tự full-width. Không nhận chữ số — cấp bậc kiểu `A`, `SSS`, `BB`
    /// là chữ, còn số đã có `<n>`/`<d>` lo.
    public static let latinLetterUnits: Set<UInt16> = makeUnits(
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
            + "ＡＢＣＤＥＦＧＨＩＪＫＬＭＮＯＰＱＲＳＴＵＶＷＸＹＺ"
            + "ａｂｃｄｅｆｇｈｉｊｋｌｍｎｏｐｑｒｓｔｕｖｗｘｙｚ"
    )
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
        case .hanNumeral: return hanNumeralUnits
        case .asciiDigits: return asciiDigitsUnits
        case .magnitude: return magnitudeUnits
        case .latinLetters: return latinLetterUnits
        }
    }

    /// `<m>`: chuỗi cơ số 10 → **chữ đơn vị** tiếng Việt (uỷ quyền cho `QuickTranslationMagnitudeFormatter`);
    /// `leadsPattern` ⇒ `十` đứng đầu mẫu đọc `mười`.
    public static func renderMagnitude(_ value: String, leadsPattern: Bool = false) -> String {
        QuickTranslationMagnitudeFormatter.renderMagnitude(value, leadsPattern: leadsPattern)
    }

    /// `<a>`: giữ đúng hoa/thường của bản gốc — `SSS级` phải ra `SSS`, không phải `sss`. Chỉ hạ full-width
    /// về ASCII, cùng chính sách với `<d>`: `ＳＳＳ` và `SSS` đọc ra một kết quả.
    public static func renderLatinLetters(_ value: String) -> String {
        var output = ""
        for char in value {
            guard let scalar = char.unicodeScalars.first, char.unicodeScalars.count == 1 else {
                output.append(char)
                continue
            }
            // Hai dải tường minh, **không** dùng một dải FF21...FF5A: khoảng giữa hai dải là dấu câu
            // full-width (`［＼］＾＿｀`), hạ chúng về ASCII ở đây là sai nếu lớp ký tự sau này mở rộng.
            let isFullWidthUpper = scalar.value >= 0xFF21 && scalar.value <= 0xFF3A
            let isFullWidthLower = scalar.value >= 0xFF41 && scalar.value <= 0xFF5A
            if isFullWidthUpper || isFullWidthLower, let ascii = Unicode.Scalar(scalar.value - 0xFEE0) {
                output.append(Character(ascii))
            } else {
                output.append(char)
            }
        }
        return output
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
    /// Điều kiện: chuỗi có đúng **một** dãy gồm **từ hai** chữ số Hán trần liền nhau. Trong tiếng Hán,
    /// các chữ số Hán trần đứng cạnh nhau mà không có từ chỉ bậc (`十百千万…`) không thể ghép thành một số
    /// chính thức (ví dụ 24 bắt buộc là `二十四`, 952 là `九百五十二`), nên chúng là các số ước lượng hoặc
    /// số được liệt kê (cả tăng dần, giảm dần hay ngẫu nhiên: `二三`, `二四`, `九五二`, `三五`, `五三`…).
    /// Giá trị từng số tính bằng cách thay cả dãy đó lần lượt bằng **một** chữ số rồi đọc chuỗi như một số
    /// thường — nhờ vậy bậc đứng trước hay sau đều đúng:
    ///
    /// * `二三` → 2, 3            (không có bậc, liền kề)
    /// * `二四` → 2, 4            (không có bậc, cách quãng)
    /// * `九五二` → 9, 5, 2       (không có bậc, giảm dần/ngẫu nhiên)
    /// * `十三四` → 13, 14        (bậc đứng trước: 十三四岁 = 13, 14 tuổi)
    /// * `三十四五` → 34, 35
    /// * `二三十` → 20, 30        (bậc đứng sau)
    /// * `三四百` → 300, 400
    /// * `三百四五十` → 340, 350  (bậc cả hai phía)
    ///
    /// Trả `nil` — tức đọc như **một** số hoặc đọc từng chữ số — cho các trường hợp:
    /// * Chỉ **một** dãy: chuỗi có hai dãy rời (`二三十四五`) thì bỏ, vì không biết ghép theo cụm nào.
    /// * **Không** chứa `零`/`〇`: `二零二五` là năm đọc theo từng chữ số (2025), không phải liệt kê.
    /// * Chuỗi toàn chữ số Hán trần không có bậc dài ≥ 4 ký tự (`一九九八`, `一九四九`): là năm 4 chữ số,
    ///   giữ nguyên đọc từng chữ số qua `renderDigitwise`.
    /// * `三百二十` không có dãy chữ số trần nào dài ≥ 2 nên vẫn ra đúng `320`.
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

        let prefix = String(chars[0..<start])
        let suffix = String(chars[(start + runLength)...])

        // Chuỗi toàn chữ số Hán trần (không có chữ bậc) có độ dài ≥ 4 (như năm 1998, 1949...)
        // đọc theo từng chữ số, không phải liệt kê.
        if prefix.isEmpty, suffix.isEmpty, runLength >= 4 {
            return nil
        }

        var numbers: [Int] = []
        for char in chars[start..<(start + runLength)] {
            guard let parsed = parseChineseNumeral(prefix + String(char) + suffix) else { return nil }
            numbers.append(parsed)
        }
        return numbers
    }

    /// Đọc một chuỗi số Hán thành `Int`; `nil` khi tràn hoặc gặp ký tự lạ. `internal` cho luật "số sau nhỏ hơn bậc đứng
    /// trước" của matcher (`QuickTranslationRuleMatcher+Numeral`).
    ///
    /// Tách theo **bậc lớn nhất** (兆 > 亿 > 万), lấy lần xuất hiện **cuối**: vế trái **nhân** bậc, vế phải cộng vào
    /// (1.3.1093). Bậc chồng nhờ vậy đọc đúng — `万亿` = 10¹², `三万五千亿` = 3,5·10¹², `两万万` = 2·10⁸ — thay cho cách cộng
    /// dồn theo *section* của reference (`一万亿` từng ra `100010000`). Bản tham chiếu: `parse_fixed` ở
    /// `Docs/Plans/token-so-lon/fix.py`.
    ///
    /// Chữ số trần đứng **cuối, ngay sau một bậc** là viết tắt của bậc **thấp hơn một cấp** (hệ số `bậc / 10`):
    /// `一万二` = 12000, `一亿五` = 150000000, `八千三` = 8300, `三百五` = 350; `二十三` vẫn 23. `零`/`〇` không phải chữ số
    /// đuôi và chữ liền trước phải là bậc ⇒ `一万零二` vẫn 10002.
    static func parseChineseNumeral(_ value: String) -> Int? {
        parseChineseNumeral(Array(value)[...])
    }

    /// Thứ tự thử bậc lớn: lớn nhất trước.
    private static let largeMagnitudeOrder: [Character] = ["兆", "亿", "億", "万", "萬"]

    private static func parseChineseNumeral(_ chars: ArraySlice<Character>) -> Int? {
        for unit in largeMagnitudeOrder {
            guard let split = chars.lastIndex(of: unit), let scale = largeMagnitudes[unit] else { continue }
            let left = chars[..<split]
            let right = chars[chars.index(after: split)...]
            guard let leftValue = left.isEmpty ? 1 : parseChineseNumeral(left) else { return nil }

            let rightValue: Int
            if right.count == 1, let last = right.first, last != "零", last != "〇",
               bareHanDigits.contains(last), let digit = digitMap[last] {
                rightValue = digit * (scale / 10)
            } else {
                let rest = right.drop(while: { $0 == "零" || $0 == "〇" })
                guard let parsed = rest.isEmpty ? 0 : parseChineseNumeral(rest) else { return nil }
                rightValue = parsed
            }

            let (head, multiplyOverflow) = leftValue.multipliedReportingOverflow(by: scale)
            let (total, addOverflow) = head.addingReportingOverflow(rightValue)
            return multiplyOverflow || addOverflow ? nil : total
        }
        return parseSmallChineseNumeral(chars)
    }

    /// Phần dưới 1 vạn: `十百千` + chữ số, kèm viết tắt đuôi (`两千五` = 2500, `三百五` = 350).
    private static func parseSmallChineseNumeral(_ chars: ArraySlice<Character>) -> Int? {
        var total = 0
        var current = 0
        for char in chars {
            if let unit = smallMagnitudes[char] {
                total += (current == 0 ? 1 : current) * unit
                current = 0
            } else if let digit = digitMap[char] {
                // Gán, không ghép `current * 10 + digit`: chữ số Hán đứng liền nhau không bao giờ là một số ghép
                // (`二三十` đã đi nhánh liệt kê trước khi tới đây), và luật "số sau nhỏ hơn bậc" của matcher cần
                // `三四千` ra 4000 chứ không phải 34000 — y bản tham chiếu `parse_small`.
                current = digit
            } else {
                return nil
            }
        }

        let array = Array(chars)
        if array.count >= 2, let last = array.last, last != "零", last != "〇", bareHanDigits.contains(last),
           let unit = smallMagnitudes[array[array.count - 2]], unit >= 100, let digit = digitMap[last] {
            return total + digit * (unit / 10)
        }
        return total + current
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
