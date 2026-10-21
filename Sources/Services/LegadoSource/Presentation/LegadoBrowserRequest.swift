import Foundation

/// Yêu cầu mở **trình duyệt hiện cho người dùng** do JS của nguồn phát (`java.startBrowser`, `startBrowserAwait`,
/// `startBrowserDp`, spec §10.8) hoặc do luồng đăng nhập web (§10.2). Presenter (UI) nhận qua
/// `LegadoPresentationEventCenter.stream` rồi trả kết quả bằng `completeBrowser(id:result:)`.
struct LegadoBrowserRequest: Sendable, Identifiable {
    let id: UUID
    /// `bookSourceUrl` nguyên văn của nguồn (khoá kho cookie).
    let sourceKey: String
    let sourceName: String
    /// URL nạp: `http(s)` hoặc `data:text/html;base64,…` (nguồn tự dựng trang cài đặt).
    let url: String
    /// Tiêu đề thanh trên (tham số `title` của JS).
    let title: String
    /// Chuỗi HTML phải nạp với URL nền = `url` (tham số 4 của `startBrowserAwait`); `nil` ⇒ nạp `url`.
    let html: String?
    /// `true` khi JS đang **chờ** (`startBrowserAwait`): presenter phải luôn trả kết quả (kể cả khi người dùng huỷ).
    /// `false` (`startBrowser`): JS đã chạy tiếp; kết quả chỉ dùng để đồng bộ cookie khi đóng.
    let waitsForResult: Bool
    /// UA nên đặt cho trình duyệt (UA WebView Android của nguồn hoặc header `User-Agent` của nguồn).
    let userAgent: String
    /// Header nguồn đã tính (gồm header đăng nhập) — presenter có thể gắn vào request đầu tiên.
    let headers: [String: String]
    /// Cookie hiện có trong kho của nguồn cho tên miền của `url`: đẩy vào `WKHTTPCookieStore` trước khi nạp.
    let cookies: [LegadoStoredCookie]

    /// Cookie dạng `HTTPCookie` để đặt vào `WKWebsiteDataStore.httpCookieStore`.
    var httpCookies: [HTTPCookie] {
        cookies.compactMap { $0.httpCookie }
    }
}
