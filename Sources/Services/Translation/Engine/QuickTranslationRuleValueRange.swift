import Foundation

/// Khoảng **giá trị** `#min-max` của token số trong rule dịch (1.3.701): `<n#1-200>`, `<d:1-3#0-99>`, `<n#5>`,
/// `<n#100->`. Khác `:min-max` (độ dài = số ký tự token nuốt): đây là giá trị con số mà token đọc ra. Độ dài luôn
/// viết **trước** `#`.
///
/// Chỉ `<n>` `<y>` `<h>` `<d>` `<hn>` (và tổ hợp `|` của chúng) nhận `#`; token khác ⇒ `INVALID_VALUE_RANGE`. Giá
/// trị lấy từ **kết quả đã render** chứ không parse lại chữ Hán, nên luôn trùng con số xuất ra bản dịch:
/// - `<n>` `<y>` `<h>` `<d>` render ra chữ số ⇒ `Int` của chuỗi đó (`007` = 7). `<n>` liệt kê (`十三四` → `13, 14`)
///   ⇒ **mọi** số phải nằm trong khoảng.
/// - `<hn>` render ra âm Hán-Việt ⇒ giá trị lấy bằng `QuickTranslationNumberFormatter.renderNumeral` của chuỗi nguồn.
/// - Kết quả không phải số nguyên (tràn `Int`, số Hán đọc không được) ⇒ **không** khớp.
///
/// Token không ghi `#` có `valueRange == nil` và matcher không gọi tới đây: rule cũ đi đúng đường cũ.
public struct QuickTranslationRuleValueRange: Sendable, Equatable {
    public var lowerBound: Int
    /// `nil` = không chặn trên (`#100-`).
    public var upperBound: Int?

    public init(lowerBound: Int, upperBound: Int?) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
    }

    /// Lỗi cú pháp của phần sau `#`; parser gói thành `INVALID_VALUE_RANGE` kèm `message`.
    public struct ParseFailure: Error, Sendable {
        public let message: String
    }

    /// Tên token nhận `#min-max`: các token đọc ra **một con số**. `<m>` ra chữ đơn vị, `<a>` là chữ cái ⇒ không nhận.
    public static let supportedTokenNames: Set<String> = ["n", "y", "h", "d", "hn"]

    public static func supports(names: [String]) -> Bool {
        !names.isEmpty && names.allSatisfy { supportedTokenNames.contains($0) }
    }

    public func contains(_ value: Int) -> Bool {
        guard value >= lowerBound else { return false }
        guard let upperBound else { return true }
        return value <= upperBound
    }

    /// Kẹp về khoảng parser nhận: số đầu `≥ 0`, số sau (nếu có) `≥` số đầu. Chỗ kẹp duy nhất cho mọi đường bấm ở màn
    /// sửa rule (`TokenSpec.clamp()` và ô số của `QuickTranslationRuleTokenValueRangeEditor`).
    public func clamped() -> QuickTranslationRuleValueRange {
        let lower = max(0, lowerBound)
        return QuickTranslationRuleValueRange(lowerBound: lower, upperBound: upperBound.map { max(lower, $0) })
    }

    /// `#1-200`, `#5`, `#100-` — đúng dạng mà `parse` đọc lại ra chính khoảng này.
    public var syntax: String {
        guard let upperBound else { return "#\(lowerBound)-" }
        return upperBound == lowerBound ? "#\(lowerBound)" : "#\(lowerBound)-\(upperBound)"
    }

    // MARK: - Cú pháp

    /// Tách phần `#…` khỏi spec token (phần giữa `<` và `>`): `n:1-4#1-200` → (`n:1-4`, `1-200`); không có `#` ⇒
    /// `valueText == nil`. Parser, `tokenSpecNames` và màn sửa rule cùng gọi hàm này nên hiểu `#` y như nhau.
    public static func split(spec: String) -> (head: String, valueText: String?) {
        guard let hash = spec.firstIndex(of: "#") else { return (spec, nil) }
        return (String(spec[..<hash]), String(spec[spec.index(after: hash)...]))
    }

    /// `1-200` / `5` / `100-` → khoảng. Số đầu bắt buộc (không chặn dưới thì viết `0-…`), chỉ chữ số ASCII,
    /// số đầu không được lớn hơn số sau — khác `:min-max` của độ dài vốn tự kẹp lặng lẽ.
    public static func parse(_ text: String) throws -> QuickTranslationRuleValueRange {
        let body = text.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else {
            throw ParseFailure(message: "Thiếu khoảng giá trị sau dấu #: viết #1-200, #5 hoặc #100-")
        }
        guard !body.contains(":") else {
            throw ParseFailure(message: "Độ dài :min-max phải viết trước khoảng giá trị, ví dụ <n:1-4#1-200>")
        }

        let bounds = body.components(separatedBy: "-")
        guard bounds.count <= 2 else {
            throw ParseFailure(message: "Khoảng giá trị #\(body) không hợp lệ: viết #1-200, #5 hoặc #100-")
        }
        guard !bounds[0].isEmpty else {
            throw ParseFailure(message: "Khoảng giá trị #\(body) thiếu số đầu; không chặn dưới thì viết #0-…")
        }
        guard let lower = integer(bounds[0]) else {
            throw ParseFailure(message: "Khoảng giá trị #\(body) không hợp lệ: chỉ dùng chữ số 0-9")
        }
        guard bounds.count == 2 else {
            return QuickTranslationRuleValueRange(lowerBound: lower, upperBound: lower)
        }
        if bounds[1].isEmpty {
            return QuickTranslationRuleValueRange(lowerBound: lower, upperBound: nil)
        }
        guard let upper = integer(bounds[1]) else {
            throw ParseFailure(message: "Khoảng giá trị #\(body) không hợp lệ: chỉ dùng chữ số 0-9")
        }
        guard lower <= upper else {
            throw ParseFailure(message: "Khoảng giá trị #\(body) ngược: số đầu lớn hơn số sau")
        }
        return QuickTranslationRuleValueRange(lowerBound: lower, upperBound: upper)
    }

    // MARK: - Kiểm giá trị

    /// Giá trị token đọc ra có nằm trong khoảng không. `rendered` = chuỗi token đã render, `source` = chuỗi nguồn
    /// token nuốt (chỉ `<hn>` cần: bản render của nó là âm Hán-Việt, không phải chữ số).
    public func accepts(
        rendered: String,
        source: String,
        kind: QuickTranslationRuleElement.NumeralKind
    ) -> Bool {
        let digits = kind == .hanNumeral ? QuickTranslationNumberFormatter.renderNumeral(source) : rendered
        // `renderNumeral` ghép số liệt kê bằng ", " (`十三四` → `13, 14`).
        for part in digits.components(separatedBy: ", ") {
            guard let value = Self.integer(part), contains(value) else { return false }
        }
        return true
    }

    /// Chuỗi toàn chữ số ASCII → `Int`; rỗng, có ký tự khác (kể cả dấu `+`/`-`) hoặc tràn ⇒ `nil`.
    private static func integer(_ text: String) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        return Int(text)
    }
}
