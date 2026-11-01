import Foundation

/// Đổi một giá trị config của tiện ích (đọc từ `plugin.json` hoặc `Extension.configJson` bằng `JSONSerialization`)
/// thành **chuỗi** — đúng hợp đồng: mọi biến config tới script đều là chuỗi (`"true"`, `"2"`), script tự ép kiểu
/// (`FLAG === "true"`, `parseInt(X)`).
///
/// Dùng ở hai chỗ, cùng một luật:
/// - `JSExecutor.injectGlobals`: biến global + `localConfig.getItem` của script. Dict kiểu gốc vẫn giữ cho code Swift
///   (`http_should_handle_cookies`, `preload_size`, `max_length`).
/// - `ExtensionConfigView`: đọc `default`/`values`/giá trị đã lưu cho màn Cấu hình.
enum ExtensionConfigValueFormatter {
    /// `JSONSerialization` trả bool dưới dạng `NSNumber`; nội suy `"\(v)"` ra `"1"`/`"0"`. Nhận diện bool thật qua
    /// `CFBoolean`. Mảng/object ⇒ chuỗi JSON (giá trị `mode: "list"`); `null` ⇒ chuỗi rỗng.
    static func text(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case is NSNull:
            return ""
        default:
            if JSONSerialization.isValidJSONObject(value),
               let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
               let json = String(data: data, encoding: .utf8) {
                return json
            }
            return "\(value)"
        }
    }

    /// Bản chuỗi của cả dict — thứ tiêm vào script.
    static func jsGlobals(from configs: [String: Any]) -> [String: String] {
        configs.mapValues(text)
    }
}
