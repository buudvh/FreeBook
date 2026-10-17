import Foundation
import JavaScriptCore

/// Đọc an toàn từng trường của `JSValue` cho các mapper media (`ComicPageMapper`, `VideoTrackMapper`).
///
/// Lý do tồn tại: `JSValue.toString()` trên `undefined`/`null` trả về chuỗi `"undefined"`/`"null"` — đọc thẳng
/// một trường tuỳ chọn (`fallback`, `script`, `referer`, `host`…) là sinh ra URL rác. Mọi trường tuỳ chọn phải
/// qua `isPresent` trước.
///
/// Chuỗi trả về là **nguyên văn** nội dung chuỗi JS (không trim) — caller tự quyết có chuẩn hoá hay không.
enum JSValueReader {
    static func isPresent(_ value: JSValue?) -> Bool {
        guard let value else { return false }
        return !value.isUndefined && !value.isNull
    }

    /// Chuỗi nguyên văn của string/number/boolean JS; `nil` với undefined/null/object/array.
    static func string(_ value: JSValue?) -> String? {
        guard let value, isPresent(value) else { return nil }
        guard value.isString || value.isNumber || value.isBoolean else { return nil }
        return value.toString()
    }

    /// Như `string(_:)` nhưng coi luôn chuỗi `"null"`/`"undefined"` là **thiếu** — script hay nối chuỗi/`String(x)`
    /// trên trường không tồn tại (vd `description: item.description` khi API không có trường đó). Dùng cho mọi
    /// trường hiển thị/định danh do script trả về (`ExtensionManager` parse search/detail/toc/genre/home…).
    static func cleanString(_ value: JSValue?) -> String? {
        guard let text = string(value), !isNullLiteral(text) else { return nil }
        return text
    }

    /// Bản cho giá trị Foundation (kết quả `parseJSObject`/`JSONSerialization`): `String`/số; `NSNull`,
    /// `"null"`, `"undefined"`, object, mảng ⇒ `nil`.
    static func cleanString(any value: Any?) -> String? {
        switch value {
        case let text as String:
            return isNullLiteral(text) ? nil : text
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    /// `"null"`/`"undefined"` (bỏ khoảng trắng hai đầu, không phân biệt hoa thường).
    static func isNullLiteral(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed == "null" || trimmed == "undefined"
    }

    /// Như `string(_:)` nhưng bỏ chuỗi rỗng/chỉ có khoảng trắng.
    static func nonEmptyString(_ value: JSValue?) -> String? {
        guard let text = string(value),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return text
    }

    /// Số nguyên từ number JS hoặc chuỗi số ("800").
    static func int(_ value: JSValue?) -> Int? {
        guard let value, isPresent(value) else { return nil }
        if value.isNumber {
            let number = value.toDouble()
            guard number.isFinite, abs(number) < Double(Int32.max) else { return nil }
            return Int(number)
        }
        if value.isString, let text = value.toString() {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let intValue = Int(trimmed) { return intValue }
            if let doubleValue = Double(trimmed), doubleValue.isFinite, abs(doubleValue) < Double(Int32.max) {
                return Int(doubleValue)
            }
        }
        return nil
    }

    /// Các phần tử của mảng JS; mảng rỗng nếu không phải mảng.
    static func array(_ value: JSValue?) -> [JSValue] {
        guard let value, isPresent(value), value.isArray else { return [] }
        let length = Int(value.forProperty("length").toInt32())
        guard length > 0 else { return [] }
        var items: [JSValue] = []
        items.reserveCapacity(length)
        for index in 0..<length {
            if let item = value.atIndex(index) { items.append(item) }
        }
        return items
    }

    /// Mảng chuỗi (bỏ phần tử rỗng/không phải chuỗi), hoặc một chuỗi đơn ⇒ mảng một phần tử.
    static func stringArray(_ value: JSValue?) -> [String] {
        guard let value, isPresent(value) else { return [] }
        if value.isArray {
            return array(value).compactMap { nonEmptyString($0) }
        }
        return nonEmptyString(value).map { [$0] } ?? []
    }

    /// `true` khi là object thường (không phải mảng).
    static func isPlainObject(_ value: JSValue?) -> Bool {
        guard let value, isPresent(value) else { return false }
        return value.isObject && !value.isArray
    }

    /// `Object.keys(value)`.
    static func keys(_ value: JSValue) -> [String] {
        guard let context = value.context,
              let objectKeys = context.objectForKeyedSubscript("Object")?.objectForKeyedSubscript("keys"),
              let keys = objectKeys.call(withArguments: [value]) else { return [] }
        if context.exception != nil {
            context.exception = nil
            return []
        }
        return array(keys).compactMap { string($0) }
    }

    /// Object `{k: v}` → `[String: String]`, chỉ giữ giá trị string/number/boolean.
    static func stringDictionary(_ value: JSValue?) -> [String: String] {
        guard let value, isPlainObject(value) else { return [:] }
        var result: [String: String] = [:]
        for key in keys(value) {
            if let text = string(value.forProperty(key)) {
                result[key] = text
            }
        }
        return result
    }

    /// `JSON.stringify(value)` phía JS — giữ đúng thứ tự khoá và cách escape của JS (không re-encode bằng
    /// `JSONSerialization`, vốn đổi `/` thành `\/` và xáo khoá).
    static func jsonString(_ value: JSValue) -> String? {
        guard let context = value.context,
              let stringify = context.objectForKeyedSubscript("JSON")?.objectForKeyedSubscript("stringify"),
              let result = stringify.call(withArguments: [value]) else { return nil }
        if context.exception != nil {
            context.exception = nil
            return nil
        }
        return string(result)
    }

    /// Chuỗi của `value` nếu là string/number; object/array ⇒ `JSON.stringify`. Dùng cho trường **opaque**
    /// (`data` của server/track).
    static func opaqueString(_ value: JSValue?) -> String? {
        guard let value, isPresent(value) else { return nil }
        if value.isString || value.isNumber || value.isBoolean { return value.toString() }
        if value.isObject { return jsonString(value) }
        return nil
    }
}
