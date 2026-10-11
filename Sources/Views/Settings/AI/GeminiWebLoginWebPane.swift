import SwiftUI
import WebKit

/// WKWebView **hiển thị** cho màn đăng nhập Google của provider Gemini Web. Dùng
/// `WKWebsiteDataStore.default()` — cùng kho cookie với WKWebView ẩn của `GeminiWebSessionController`,
/// nên đăng nhập ở đây là phiên ẩn dùng được ngay. Báo `onReachedGemini` đúng một lần khi điều hướng
/// tới `gemini.google.com` (đích của tham số `continue`).
///
/// **1.3.511 — chuyển sang Gmail để bấm số rồi quay lại thì trang về bước đầu.** Khi app ở nền, iOS có thể kết
/// thúc tiến trình WebContent; nếu delegate **không** implement `webViewWebContentProcessDidTerminate` thì WebKit
/// tự tải lại trang khi view hiện lại (`WebPageProxy::tryReloadAfterProcessTermination`), và trang xác minh của
/// Google mất trạng thái nên quay về bước nhập email. Ở đây implement hàm đó: **không** tự tải lại (tự gọi
/// `reload()` trong callback phá lớp chống vòng lặp crash 1 lần/30 s của WebKit), chỉ báo lên View để hiện nút
/// "Tải lại" cho người dùng bấm. Mọi điều hướng đều có log host + path (không query: query chứa token).
struct GeminiWebLoginWebPane: UIViewRepresentable {
    let url: URL
    /// Tăng lên để yêu cầu tải lại trang hiện tại (nút "Tải lại" sau khi iOS giải phóng trang).
    let reloadToken: Int
    let onNavigate: (URL?) -> Void
    let onReachedGemini: () -> Void
    let onProcessTerminated: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onReachedGemini: onReachedGemini, onProcessTerminated: onProcessTerminated)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = GeminiWebSessionController.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.appliedReloadToken = reloadToken
        // Hai dòng "tạo WKWebView" trong một lần mở sheet ⇒ SwiftUI dựng lại pane (khác nguyên nhân iOS giải phóng trang).
        AppLogger.shared.log("🤖 [GeminiWebLogin] Tạo WKWebView đăng nhập #\(context.coordinator.instanceId)")
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        guard reloadToken != context.coordinator.appliedReloadToken else { return }
        context.coordinator.appliedReloadToken = reloadToken
        AppLogger.shared.log("🤖 [GeminiWebLogin] Người dùng bấm Tải lại: \(Coordinator.describe(uiView.url))")
        if uiView.url == nil {
            uiView.load(URLRequest(url: url))
        } else {
            uiView.reload()
        }
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let instanceId = String(UUID().uuidString.prefix(4))
        var appliedReloadToken = 0
        private let onNavigate: (URL?) -> Void
        private let onReachedGemini: () -> Void
        private let onProcessTerminated: () -> Void
        private var reported = false

        init(
            onNavigate: @escaping (URL?) -> Void,
            onReachedGemini: @escaping () -> Void,
            onProcessTerminated: @escaping () -> Void
        ) {
            self.onNavigate = onNavigate
            self.onReachedGemini = onReachedGemini
            self.onProcessTerminated = onProcessTerminated
        }

        /// Chỉ host + path: query/fragment của trang đăng nhập Google mang token, không được log.
        static func describe(_ url: URL?) -> String {
            guard let url else { return "-" }
            return (url.host ?? "-") + url.path
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            AppLogger.shared.log("🤖 [GeminiWebLogin] #\(instanceId) bắt đầu điều hướng: \(Self.describe(webView.url))")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            AppLogger.shared.log("🤖 [GeminiWebLogin] #\(instanceId) commit: \(Self.describe(webView.url))")
            onNavigate(webView.url)
            check(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigate(webView.url)
            check(webView.url)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLogger.shared.log("🤖 [GeminiWebLogin] #\(instanceId) lỗi tại \(Self.describe(webView.url)): \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            AppLogger.shared.log("🤖 [GeminiWebLogin] #\(instanceId) lỗi khi mở \(Self.describe(webView.url)): \(error.localizedDescription)")
        }

        /// Implement để WebKit **không** tự tải lại (xem doc của type); người dùng quyết định bằng nút "Tải lại".
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            AppLogger.shared.log("🤖 [GeminiWebLogin] #\(instanceId) iOS kết thúc tiến trình web của trang đăng nhập (\(Self.describe(webView.url)))")
            onProcessTerminated()
        }

        private func check(_ url: URL?) {
            guard !reported, let host = url?.host?.lowercased(), host == "gemini.google.com" else { return }
            reported = true
            onReachedGemini()
        }
    }
}
