import Foundation

/// Khối tuỳ chọn JSON đứng sau URL: `url,{"method":"POST","body":…,"charset":"gbk"}`.
///
/// Port `AnalyzeUrl.UrlOption` (`:781-947`). Các khoá ngoài phạm vi (`webView`, `js` đã xử lý riêng,
/// `dnsIp`, `serverID`) vẫn được đọc để báo lên báo cáo tương thích.
public struct LegadoUrlOption {
    public let method: String?
    public let charset: String?
    public let headers: [String: String]
    /// Body dạng chuỗi đã chuẩn hoá: object/array được encode lại thành JSON.
    public let body: String?
    /// Body gốc là JSON (object hoặc array) ⇒ gửi nguyên với `Content-Type: application/json`.
    public let bodyIsJSON: Bool
    public let retry: Int?
    public let type: String?
    public let origin: String?
    public let webView: Bool
    public let js: String?
    public let bodyJs: String?

    public init(json: [String: Any]) {
        method = LegadoJSON.string(json["method"])?.uppercased()
        charset = LegadoJSON.string(json["charset"])
        headers = LegadoJSON.headerMap(json["headers"])

        let rawBody = json["body"]
        if let dict = rawBody as? [String: Any] {
            body = LegadoJSON.encode(dict)
            bodyIsJSON = true
        } else if let list = rawBody as? [Any] {
            body = LegadoJSON.encode(list)
            bodyIsJSON = true
        } else if let text = LegadoJSON.string(rawBody) {
            body = text
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            bodyIsJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
        } else {
            body = nil
            bodyIsJSON = false
        }

        retry = LegadoJSON.int(json["retry"])
        type = LegadoJSON.string(json["type"])
        origin = LegadoJSON.string(json["origin"])
        // `webView` có thể là bool, số, hoặc chuỗi rỗng khác nil — Legado chỉ xét "có khai hay không".
        if let raw = json["webView"] {
            webView = LegadoJSON.bool(raw) ?? !(LegadoJSON.string(raw) ?? "").isEmpty
        } else {
            webView = false
        }
        js = LegadoJSON.string(json["js"])
        bodyJs = LegadoJSON.string(json["bodyJs"])
    }

    /// Tách URL thành phần địa chỉ và phần tuỳ chọn.
    ///
    /// Legado dùng `paramPattern = "\\s*,\\s*(?=\\{)"` (`:768`) — dấu phẩy **đứng trước `{`**. Không
    /// thể chỉ tìm dấu phẩy đầu tiên vì URL query hoàn toàn có thể chứa dấu phẩy.
    public static func split(_ raw: String) -> (url: String, option: LegadoUrlOption?) {
        guard let range = raw.range(of: #"\s*,\s*(?=\{)"#, options: .regularExpression) else {
            return (raw, nil)
        }
        let url = String(raw[raw.startIndex..<range.lowerBound])
        let optionText = String(raw[range.upperBound...])
        guard let data = optionText.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // JSON không hợp lệ: Legado log cảnh báo rồi bỏ qua khối tuỳ chọn.
            AppLogger.shared.log("⚠️ [LegadoUrl] Khối tuỳ chọn không phải JSON hợp lệ, bỏ qua: \(optionText.prefix(120))")
            return (url, nil)
        }
        return (url, LegadoUrlOption(json: json))
    }
}
