import SwiftUI
import WebKit

/// WKWebView **hiển thị** cho màn đăng nhập Google của provider Gemini Web. Dùng
/// `WKWebsiteDataStore.default()` — cùng kho cookie với WKWebView ẩn của `GeminiWebSessionController`,
/// nên đăng nhập ở đây là phiên ẩn dùng được ngay. Báo `onReachedGemini` đúng một lần khi điều hướng
/// tới `gemini.google.com` (đích của tham số `continue`).
struct GeminiWebLoginWebPane: UIViewRepresentable {
    let url: URL
    let onNavigate: (URL?) -> Void
    let onReachedGemini: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onReachedGemini: onReachedGemini)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = GeminiWebSessionController.userAgent
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.navigationDelegate = nil
        uiView.stopLoading()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onNavigate: (URL?) -> Void
        private let onReachedGemini: () -> Void
        private var reported = false

        init(onNavigate: @escaping (URL?) -> Void, onReachedGemini: @escaping () -> Void) {
            self.onNavigate = onNavigate
            self.onReachedGemini = onReachedGemini
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            onNavigate(webView.url)
            check(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onNavigate(webView.url)
            check(webView.url)
        }

        private func check(_ url: URL?) {
            guard !reported, let host = url?.host?.lowercased(), host == "gemini.google.com" else { return }
            reported = true
            onReachedGemini()
        }
    }
}
