import Foundation

/// Phản hồi đã giải mã của một request nguồn Legado.
struct LegadoHTTPResponse {
    /// URL đã gửi (chặng đầu).
    var requestURL: String
    /// URL cuối sau chuyển hướng — URL nền cho bước sau (§4.7, §2.15).
    var finalURL: String
    var statusCode: Int
    /// Header của chặng cuối (tên giữ nguyên cách viết của máy chủ).
    var headers: [String: String]
    /// Cookie do phản hồi này đặt (`Set-Cookie`, mọi chặng), tên → giá trị — cho `response.cookies()` (§6.4.1).
    var cookies: [String: String]
    /// Thân đã giải mã theo §4.5 (WebView: HTML trang hoặc giá trị `webJs`).
    var body: String
    var data: Data

    var message: String {
        statusCode == 0 ? "" : HTTPURLResponse.localizedString(forStatusCode: statusCode)
    }

    func header(_ name: String) -> String? {
        headers.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    /// Nội dung để phân tích rule: JSON nếu thân là JSON, ngược lại tài liệu HTML (§5.1.1 bước 2).
    var content: LegadoContentNode {
        LegadoContentNode.from(body: body, baseUrl: finalURL)
    }
}
