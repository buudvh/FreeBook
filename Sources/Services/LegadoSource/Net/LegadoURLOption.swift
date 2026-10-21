import Foundation

/// Khối option `,{…}` sau URL (spec §3.6). Khoá so không phân biệt hoa thường; khoá lạ bị bỏ qua.
struct LegadoURLOption {
    var method: String?
    /// Chuỗi (form hoặc văn bản JSON) hoặc object/mảng JSON (§3.9).
    var body: LegadoEngineJSON?
    var charset: String?
    var headers: [(name: String, value: String)] = []
    var webView = false
    /// Mili giây chờ thêm sau khi trang tải xong.
    var webViewDelayTime: Double?
    var js: String?
    var retry: Int?
    /// Nhãn tự đặt (`jjwx`, `qm`…); ở nguồn chữ không có tác dụng, chỉ giữ lại.
    var type: String?

    /// `nil` khi văn bản không phải object (parse lenient, §1.2.1).
    static func parse(_ text: String) -> LegadoURLOption? {
        guard let json = LegadoEngineJSONParser.parse(text, lenient: true), let entries = json.objectEntries else {
            return nil
        }
        var option = LegadoURLOption()
        for entry in entries {
            let value = entry.value
            switch entry.key.lowercased() {
            case "method":
                let method = value.scalarString.trimmingCharacters(in: .whitespaces).uppercased()
                option.method = method.isEmpty ? nil : method
            case "body":
                option.body = value.isNull ? nil : value
            case "charset":
                let charset = value.scalarString.trimmingCharacters(in: .whitespaces)
                option.charset = charset.isEmpty ? nil : charset
            case "headers":
                option.headers = LegadoHeaderParser.pairs(from: value)
            case "webview":
                option.webView = LegadoRuleValue.isTruthy(value.scalarString)
            case "webviewdelaytime":
                option.webViewDelayTime = value.doubleValue
            case "js":
                let code = value.scalarString
                option.js = code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : code
            case "retry":
                option.retry = value.doubleValue.flatMap { $0.isFinite && abs($0) < 1000 ? Int($0) : nil }
            case "type":
                option.type = value.scalarString
            default:
                continue
            }
        }
        return option
    }
}
