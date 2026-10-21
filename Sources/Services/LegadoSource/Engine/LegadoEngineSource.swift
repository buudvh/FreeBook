import Foundation

/// Bối cảnh nguồn mà engine cần (độc lập với model lưu trữ): lớp ráp nối ánh xạ model nguồn → struct này.
///
/// `rawJSON` là **object JSON gốc** của nguồn: `source.*` trong JS đọc mọi khoá nguyên văn từ đây (§6.5 —
/// `eval(String(source.bookSourceComment))`). Các trường tường minh là giá trị đã decode khoan dung (§1.2).
struct LegadoEngineSource: Sendable {
    /// `bookSourceUrl` **nguyên văn** (gồm `#…`): khoá định danh, `source.getKey()`, khoá rate limiter/cookie/cache.
    var key: String
    var name: String
    var group: String
    /// `bookSourceType` (0 chữ, 1 audio, 2 tranh, 3 tệp, 4 video).
    var type: Int
    /// `header` thô: JSON (lenient), `@js:`/`<js>`, hoặc dạng khác (§3.10).
    var header: String
    /// `jsLib` thô: mã JS hoặc JSON `{tên: url}` (§5.8).
    var jsLib: String
    /// `concurrentRate` thô (§4.1).
    var concurrentRate: String
    var enabledCookieJar: Bool
    var loginUrl: String
    var rawJSON: String

    init(key: String, name: String = "", group: String = "", type: Int = 0, header: String = "", jsLib: String = "",
         concurrentRate: String = "", enabledCookieJar: Bool = false, loginUrl: String = "", rawJSON: String = "") {
        self.key = key
        self.name = name
        self.group = group
        self.type = type
        self.header = header
        self.jsLib = jsLib
        self.concurrentRate = concurrentRate
        self.enabledCookieJar = enabledCookieJar
        self.loginUrl = loginUrl
        self.rawJSON = rawJSON
    }

    /// Dựng thẳng từ object JSON của một nguồn (decode khoan dung tối thiểu). Dùng cho công cụ/bộ nghiệm thu khi chưa
    /// có model lưu trữ; `nil` khi văn bản không phải object có `bookSourceUrl`.
    static func from(json text: String) -> LegadoEngineSource? {
        guard let object = LegadoEngineJSONParser.parse(text, lenient: true), object.objectEntries != nil,
              let key = object["bookSourceUrl"]?.scalarString else { return nil }
        func string(_ name: String) -> String {
            guard let value = object[name], !value.isNull else { return "" }
            return value.scalarString
        }
        let typeValue = object["bookSourceType"]?.doubleValue ?? 0
        let cookieJar = object["enabledCookieJar"].map { LegadoRuleValue.isTruthy($0.scalarString) } ?? false
        return LegadoEngineSource(
            key: key, name: string("bookSourceName"), group: string("bookSourceGroup"),
            type: typeValue.isFinite && abs(typeValue) < 1_000_000 ? Int(typeValue) : 0, header: string("header"), jsLib: string("jsLib"),
            concurrentRate: string("concurrentRate"), enabledCookieJar: cookieJar, loginUrl: string("loginUrl"),
            rawJSON: text
        )
    }

    /// URL gốc để ghép URL tương đối (§1.4): bỏ `#…`, trim; `""` khi khoá không phải URL.
    var baseURL: String {
        LegadoURLResolver.sourceBaseURL(key)
    }

    /// Object cho `source` trong JS: object gốc (giữ thứ tự khoá), đảm bảo có các khoá engine biết.
    var jsObject: LegadoEngineJSON {
        var entries = LegadoEngineJSONParser.parse(rawJSON, lenient: true)?.objectEntries ?? []
        func ensure(_ name: String, _ value: LegadoEngineJSON) {
            if !entries.contains(where: { $0.key == name }) { entries.append((key: name, value: value)) }
        }
        ensure("bookSourceUrl", .string(key))
        ensure("bookSourceName", .string(name))
        ensure("bookSourceGroup", .string(group))
        ensure("bookSourceType", .fromNumber(Double(type)))
        ensure("header", .string(header))
        ensure("jsLib", .string(jsLib))
        ensure("loginUrl", .string(loginUrl))
        ensure("enabledCookieJar", .bool(enabledCookieJar))
        ensure("concurrentRate", .string(concurrentRate))
        return .object(entries)
    }
}
