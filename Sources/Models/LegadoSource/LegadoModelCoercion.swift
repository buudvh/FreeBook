import Foundation

/// Ép kiểu khoan dung cho giá trị JSON của nguồn Legado (spec §1.2): số-hoặc-chuỗi, bool-hoặc-số-hoặc-chuỗi,
/// `null` = vắng mặt. Đầu vào là kiểu Foundation do `JSONSerialization` / `LegadoModelJSON` trả về.
enum LegadoModelCoercion {
    /// `NSNumber` mang giá trị bool (`true`/`false` của JSON) — phân biệt với số `0`/`1`.
    static func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }

    /// Giá trị → chuỗi: chuỗi giữ nguyên; số → thập phân; bool → `"true"`/`"false"`; object/mảng → chuỗi JSON;
    /// `null`/vắng ⇒ `nil`.
    static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let text = value as? String { return text }
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue ? "true" : "false" }
            return numberString(number)
        }
        if let object = value as? [String: Any] { return LegadoModelJSON.serializedString(object) }
        if let array = value as? [Any] { return LegadoModelJSON.serializedString(array) }
        return String(describing: value)
    }

    /// Số nguyên từ số (`0`, `0.0`) hoặc chuỗi số (`"0"`, `"0.0"`). Bool / không parse được ⇒ `nil`.
    static func int(_ value: Any?) -> Int? {
        int64(value).flatMap { Int(exactly: $0) }
    }

    static func int64(_ value: Any?) -> Int64? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber {
            guard !isBoolean(number) else { return nil }
            return int64(fromDouble: number.doubleValue) ?? number.int64Value
        }
        if let text = value as? String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let integer = Int64(trimmed) { return integer }
            if let double = Double(trimmed) { return int64(fromDouble: double) }
        }
        return nil
    }

    /// Bool từ bool, số `0`/`1`, hoặc chuỗi `"true"`/`"false"`/`"1"`/`"0"` (không phân biệt hoa thường).
    /// Giá trị khác ⇒ `nil` (caller dùng mặc định).
    static func bool(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber {
            if isBoolean(number) { return number.boolValue }
            switch number.doubleValue {
            case 0: return false
            case 1: return true
            default: return nil
            }
        }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    /// Mọi khoá của một nhóm rule → chuỗi. Nhóm là object, hoặc **chuỗi** chứa JSON object (parse lenient);
    /// dạng khác / lỗi ⇒ nhóm rỗng (spec §1.2).
    static func stringMap(_ group: Any?) -> [String: String] {
        let object: [String: Any]?
        if let dictionary = group as? [String: Any] {
            object = dictionary
        } else if let text = group as? String {
            object = LegadoModelJSON.parseObject(text)
        } else {
            object = nil
        }
        guard let object else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in object {
            if let text = string(raw) { result[key] = text }
        }
        return result
    }

    // MARK: - Helpers

    private static func numberString(_ number: NSNumber) -> String {
        if let integer = int64(fromDouble: number.doubleValue) { return String(integer) }
        return number.stringValue
    }

    /// Chỉ nhận số thực **không có phần lẻ** và nằm trong khoảng chính xác của `Double`.
    private static func int64(fromDouble double: Double) -> Int64? {
        guard double.isFinite, double.rounded() == double, abs(double) < 9.0e15 else { return nil }
        return Int64(double)
    }
}
