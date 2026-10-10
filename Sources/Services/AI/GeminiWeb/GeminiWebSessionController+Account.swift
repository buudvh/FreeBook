import Foundation
import WebKit

/// Trạng thái đăng nhập Google của Gemini Web — đọc/xoá cookie ở `WKWebsiteDataStore.default()`, kho
/// dùng chung với `GeminiWebLoginView` và trình duyệt bypass.
extension GeminiWebSessionController {
    func isSignedIn() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { $0.name == "__Secure-1PSID" && $0.domain.hasSuffix("google.com") }
    }

    /// Xoá mọi cookie `*.google.com` của kho mặc định — **cũng** đăng xuất Google trong trình duyệt bypass của app.
    func signOut() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        for cookie in cookies where cookie.domain.hasSuffix("google.com") {
            await store.deleteCookie(cookie)
        }
        invalidateSession()
        releaseWebView()
        AppLogger.shared.log("🤖 [GeminiWeb] Đã đăng xuất Google (xoá cookie *.google.com)")
    }
}
