import Foundation

/// Kết quả presenter trả cho một `LegadoBrowserRequest` khi người dùng bấm "Xong" (✓) hoặc huỷ.
struct LegadoBrowserResult: Sendable {
    /// `document.documentElement.outerHTML` của trang lúc đóng (rỗng nếu không lấy được).
    var html: String
    /// URL hiện tại của trang lúc đóng.
    var finalURL: String
    /// Cookie của các tên miền đã ghé (đọc từ `WKWebsiteDataStore`), sẽ được gộp vào kho cookie của nguồn.
    var cookies: [LegadoStoredCookie]
    /// Người dùng bấm Huỷ (vẫn trả trạng thái trang — nguồn tự kiểm `body()`).
    var cancelled: Bool

    init(html: String, finalURL: String, cookies: [LegadoStoredCookie], cancelled: Bool) {
        self.html = html
        self.finalURL = finalURL
        self.cookies = cookies
        self.cancelled = cancelled
    }

    /// Tiện cho presenter: nhận thẳng cookie của WebKit.
    init(html: String, finalURL: String, httpCookies: [HTTPCookie], cancelled: Bool) {
        self.init(html: html, finalURL: finalURL, cookies: httpCookies.map { LegadoStoredCookie(httpCookie: $0) },
                  cancelled: cancelled)
    }

    /// Kết quả "không có người dùng" (không trình bày được).
    static let unavailable = LegadoBrowserResult(html: "", finalURL: "", cookies: [], cancelled: true)
}
