import Foundation

/// Bộ đọc JSON khoan dung cho nguồn Legado.
///
/// File nguồn thật ngoài đời khai kiểu **lệch** với `BookSource.kt`: `lastUpdateTime` là chuỗi
/// `"1788232204348"` trong khi Kotlin khai `Long`, `enabled*` có thể là `0/1` thay vì bool, và 5 nhóm
/// rule có thể là object **hoặc** một chuỗi JSON đã escape (GSON nhận cả hai qua `jsonDeserializer`;
/// `Codable` của Swift thì không). Vì vậy toàn bộ phân hệ đọc nguồn bằng `[String: Any]` qua
/// `JSONSerialization` rồi lấy field qua đây, thay vì `Codable`.
public enum LegadoJSON {

    /// Chuỗi từ mọi kiểu vô hướng. Trả `nil` khi rỗng sau trim để caller coi như "không khai".
    public static func string(_ value: Any?) -> String? {
        guard let value else { return nil }
        let raw: String
        switch value {
        case let text as String:
            raw = text
        case let number as NSNumber:
            // NSNumber bool và số nguyên đều tới đây; `%.0f` tránh đuôi ".0" của Double.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                raw = number.boolValue ? "true" : "false"
            } else if number.doubleValue == number.doubleValue.rounded() &&
                        abs(number.doubleValue) < 9_007_199_254_740_992 {
                raw = String(number.int64Value)
            } else {
                raw = number.stringValue
            }
        default:
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : raw
    }

    /// Số nguyên từ number **hoặc** chuỗi số.
    public static func int(_ value: Any?) -> Int? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? 1 : 0 }
            return number.intValue
        case let text as String:
            return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return nil
        }
    }

    /// Bool từ bool, số (`0`/`1`) hoặc chuỗi (`"true"`, `"1"`).
    public static func bool(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return number.intValue != 0
        case let text as String:
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes": return true
            case "false", "0", "no": return false
            default: return nil
            }
        default:
            return nil
        }
    }

    /// Object từ dictionary **hoặc** chuỗi JSON đã escape.
    public static func object(_ value: Any?) -> [String: Any]? {
        if let dict = value as? [String: Any] { return dict }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    /// Mảng từ array **hoặc** chuỗi JSON đã escape.
    public static func array(_ value: Any?) -> [Any]? {
        if let list = value as? [Any] { return list }
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("["), let data = trimmed.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [Any]
    }

    /// Chuỗi header dạng JSON (`"{\"User-Agent\":\"…\"}"`) → map. Bỏ giá trị không phải vô hướng.
    public static func headerMap(_ value: Any?) -> [String: String] {
        guard let dict = object(value) else { return [:] }
        var result: [String: String] = [:]
        for (key, raw) in dict {
            if let text = string(raw) { result[key] = text }
        }
        return result
    }

    /// Serialize lại thành chuỗi JSON gọn (dùng khi JS cần nhận chuỗi, ví dụ `source.getLoginHeader()`).
    public static func encode(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value) else {
            // Vô hướng: JSONSerialization từ chối top-level không phải object/array.
            return string(value)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
