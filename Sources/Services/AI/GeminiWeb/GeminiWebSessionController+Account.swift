import Foundation
import WebKit

/// Trạng thái đăng nhập Google của Gemini Web — đọc/xoá cookie ở `WKWebsiteDataStore.default()`, kho
/// dùng chung với trình duyệt bypass (nơi `GeminiWebLoginLauncher` mở trang đăng nhập).
extension GeminiWebSessionController {
    func isSignedIn() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { $0.name == "__Secure-1PSID" && $0.domain.hasSuffix("google.com") }
    }

    /// Xoá mọi cookie `*.google.com` của kho mặc định — **cũng** đăng xuất Google trong trình duyệt bypass của app.
    ///
    /// 1.3.616: xoá luôn **tài khoản** vừa đăng xuất ở mọi provider đang giữ nó (khớp theo phiên); tài khoản khác giữ
    /// nguyên để còn xoay vòng.
    func signOut() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        let googleCookies = GoogleAccount.googleCookies(of: cookies)
        let fingerprint = GoogleAccount.fingerprint(of: googleCookies)
        for cookie in googleCookies {
            await store.deleteCookie(cookie)
        }
        if let fingerprint {
            GoogleAccountStore.deleteAll(matchingFingerprint: fingerprint)
        }
        invalidateSession()
        releaseWebView()
        AppLogger.shared.log("🤖 [GeminiWeb] Đã đăng xuất Google (xoá cookie *.google.com)")
    }

    /// Mở sheet đăng nhập: bỏ WKWebView ẩn (một tiến trình WebContent) nếu đang rảnh để bớt RAM — giảm khả năng
    /// iOS giải phóng trang đăng nhập khi người dùng sang Gmail bấm số. Sau đăng nhập phiên vốn được nạp lại.
    func releaseWebViewIfIdle() {
        guard isIdle else { return }
        AppLogger.shared.log("🤖 [GeminiWeb] Mở đăng nhập — giải phóng WKWebView ẩn để bớt RAM")
        releaseWebView()
    }
}
