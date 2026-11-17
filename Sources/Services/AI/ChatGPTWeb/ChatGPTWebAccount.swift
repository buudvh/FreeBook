import Foundation
import WebKit

/// Trạng thái đăng nhập ChatGPT của provider ChatGPT Web (1.3.971) — đọc / xoá cookie ở `WKWebsiteDataStore.default()`,
/// kho dùng chung với trình duyệt bypass (nơi người dùng đăng nhập qua `ChatGPTWebBrowserLauncher`).
///
/// Đăng nhập là **tuỳ chọn**: chưa đăng nhập thì provider chạy trang ẩn danh. Hai nguồn trạng thái:
/// - `ChatGPTWebSessionController.lastPageSignedIn` — kiểu trang thật mà lượt gần nhất gặp (chắc chắn, nhưng chỉ có sau
///   một lượt trong lần mở app này);
/// - cookie phiên (`…session-token…` trên `chatgpt.com`) — tên cookie **chưa kiểm được** (cookie HttpOnly, không đọc được
///   từ trang lúc thử) nên chỉ là phỏng đoán, UI ghi rõ.
@MainActor
enum ChatGPTWebAccount {
    enum Status: Sendable, Equatable {
        /// Lượt gần nhất chạy trên trang đã đăng nhập / ẩn danh.
        case observed(signedIn: Bool)
        /// Chưa có lượt nào trong lần mở app này — đoán theo cookie.
        case guessed(signedIn: Bool)
    }

    static func status() async -> Status {
        if let observed = ChatGPTWebSessionController.shared.lastPageSignedIn {
            return .observed(signedIn: observed)
        }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let hasSession = cookies.contains { isChatGPTDomain($0.domain) && $0.name.contains("session-token") }
        return .guessed(signedIn: hasSession)
    }

    /// Xoá mọi cookie `*.chatgpt.com` / `*.openai.com` của kho mặc định — **cũng** đăng xuất ChatGPT trong trình duyệt
    /// bypass của app. Sau đó provider chạy lại trang ẩn danh.
    static func signOut() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        var removed = 0
        for cookie in cookies where isChatGPTDomain(cookie.domain) {
            await store.deleteCookie(cookie)
            removed += 1
        }
        ChatGPTWebSessionController.shared.forgetAccountState()
        AppLogger.shared.log("🤖 [ChatGPTWeb] Đã đăng xuất ChatGPT (xoá \(removed) cookie *.chatgpt.com / *.openai.com)")
    }

    private static func isChatGPTDomain(_ domain: String) -> Bool {
        let host = domain.lowercased()
        let bare = host.hasPrefix(".") ? String(host.dropFirst()) : host
        return bare == "chatgpt.com" || bare.hasSuffix(".chatgpt.com") || bare == "openai.com" || bare.hasSuffix(".openai.com")
    }
}
