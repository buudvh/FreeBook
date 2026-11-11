import Foundation
import JavaScriptCore

/// Đọc kết quả của script tiện ích dịch (`Response.success(data)` / `Response.error(message)`).
///
/// - `translate.js`: `data` là chuỗi hoặc `{ text, segments }` (`segments` chưa dùng); dạng khác là lỗi.
/// - `language.js` / `model.js` / `style.js`: `data` là mảng object.
/// - `Response.error(message)` ⇒ `ExtensionManagerError.sourceResponse(message)` để giao diện hiện đúng chữ của tiện ích.
enum TranslationExtensionResultParser {
    struct ShapeError: LocalizedError {
        let detail: String
        var errorDescription: String? { detail }
    }

    /// Bản dịch của một lần gọi `translate.js`.
    static func translatedText(from value: JSValue) throws -> String {
        let data = try payload(of: value)
        if data.isString, let text = data.toString() { return text }
        if data.isObject, let textValue = data.objectForKeyedSubscript("text"), textValue.isString,
           let text = textValue.toString() {
            return text
        }
        throw ShapeError(detail: "Tiện ích dịch trả kết quả sai dạng (cần chuỗi hoặc { text })")
    }

    /// Mảng object của `language.js` / `model.js` / `style.js`; phần tử không phải object bị bỏ.
    static func objectList(from value: JSValue) throws -> [[String: Any]] {
        let data = try payload(of: value)
        guard data.isArray, let array = data.toArray() else {
            throw ShapeError(detail: "Tiện ích dịch trả danh sách sai dạng")
        }
        return array.compactMap { $0 as? [String: Any] }
    }

    /// Phần `data` của `Response.success`; script trả thẳng giá trị (không bọc `Response`) thì dùng chính nó.
    private static func payload(of value: JSValue) throws -> JSValue {
        guard value.isObject,
              let success = value.objectForKeyedSubscript("success"),
              !success.isUndefined, !success.isNull else {
            return value
        }
        guard success.toBool() else {
            var text = "Tiện ích dịch báo lỗi"
            if let message = value.objectForKeyedSubscript("message"), !message.isUndefined, !message.isNull,
               let messageText = message.toString(), !messageText.isEmpty {
                text = messageText
            }
            throw ExtensionManagerError.sourceResponse(message: text)
        }
        guard let data = value.objectForKeyedSubscript("data"), !data.isUndefined, !data.isNull else {
            throw ShapeError(detail: "Tiện ích dịch không trả dữ liệu")
        }
        return data
    }

    /// Chữ lỗi gọn để hiện cho người dùng (một dòng, tối đa 140 ký tự).
    static func shortMessage(for error: Error) -> String {
        let raw = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        let oneLine = raw.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > 140 ? String(oneLine.prefix(140)) + "…" : oneLine
    }
}
