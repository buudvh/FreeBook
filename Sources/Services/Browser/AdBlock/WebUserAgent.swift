import Foundation

/// User-Agent dùng chung cho mọi webview của app.
enum WebUserAgent {
    /// Safari iPhone iOS 17 — **nguyên văn** chuỗi cứng trước đây nằm rải ở `BypassBrowserTab`, `WebViewLoader`,
    /// `VisibleWebViewController`. Không đổi: trang/tiện ích đang chạy ổn với đúng chuỗi này.
    static let mobile = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    /// Safari macOS — đi kèm `WKWebpagePreferences.preferredContentMode = .desktop` cho chế độ Máy tính.
    static let desktop = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
}
