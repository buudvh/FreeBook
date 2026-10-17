import SwiftUI
import WebKit

/// WebView **hiển thị** cho kế hoạch `.embed` (track `webview` không bắt được link media):
/// nhúng nguyên trang xem để người dùng bấm play trong trang. Không có timeSkip, phụ đề hay lưu giây.
///
/// `updateUIView` chạy theo mỗi lần màn cha vẽ lại ⇒ so với nội dung đã nạp trong Coordinator,
/// chỉ nạp lại khi thật sự đổi trang. Trang chỉ nhận `User-Agent` và `Referer` (hợp đồng extension), lấy từ `EmbedContent`.
///
/// `pauseRequest` (`VideoPlaybackSession.embedPauseRequest`) đổi ⇒ dừng mọi media của trang (TTS bắt đầu đọc); giá
/// trị lúc tạo WebView chỉ làm mốc, không dừng.
struct VideoEmbedWebView: UIViewRepresentable {
    let content: VideoPlaybackSession.EmbedContent
    let pauseRequest: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsPictureInPictureMediaPlayback = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.navigationDelegate = context.coordinator
        context.coordinator.appliedPauseRequest = pauseRequest
        context.coordinator.load(content, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(content, into: webView)
        if context.coordinator.appliedPauseRequest != pauseRequest {
            context.coordinator.appliedPauseRequest = pauseRequest
            webView.pauseAllMediaPlayback(completionHandler: {})
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Gỡ delegate trước: trang trống dưới đây không được bị luật chặn điều hướng huỷ. Dừng hẳn media của trang;
        // nếu không, tiếng phim còn chạy sau khi rời màn.
        webView.navigationDelegate = nil
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        coordinator.reset()
    }

    /// Chặn quảng cáo chuyển hướng: domain trong danh sách chặn chung (`isEngineDomainBlocked`) bị huỷ ở mọi frame;
    /// sau khi trang đầu nạp xong, khung chính (main frame) không được rời host của trang đó — iframe vẫn tự do.
    final class Coordinator: NSObject, WKNavigationDelegate {
        /// Lượt yêu cầu dừng media đã áp dụng (`VideoEmbedWebView.pauseRequest`).
        var appliedPauseRequest = 0
        private var loadedContent: VideoPlaybackSession.EmbedContent?
        /// Host khung chính sau lần nạp đầu (cập nhật tới `didFinish` để chuyển hướng lúc nạp vẫn đi qua).
        private var pinnedHost: String?
        private var isInitialLoadFinished = false

        func load(_ content: VideoPlaybackSession.EmbedContent, into webView: WKWebView) {
            guard loadedContent != content else { return }
            loadedContent = content
            pinnedHost = nil
            isInitialLoadFinished = false
            switch content {
            case .page(let url, let referer, let userAgent):
                webView.customUserAgent = userAgent
                var request = URLRequest(url: url)
                if let referer, !referer.isEmpty {
                    request.setValue(referer, forHTTPHeaderField: "Referer")
                }
                webView.load(request)
            case .html(let html, let baseURL, let userAgent):
                webView.customUserAgent = userAgent
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func reset() {
            loadedContent = nil
            pinnedHost = nil
            isInitialLoadFinished = false
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if isEngineDomainBlocked(url.absoluteString) {
                decisionHandler(.cancel)
                return
            }
            // `targetFrame == nil` = mở cửa sổ mới (popup quảng cáo) ⇒ xét như khung chính.
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            if isMainFrame, isInitialLoadFinished, Self.isWebURL(url), !Self.host(url.host, isWithin: pinnedHost) {
                AppLogger.shared.log("🚫 [VideoEmbed] Chặn khung chính rời host trang nhúng: \(url.host ?? "?")")
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            guard !isInitialLoadFinished else { return }
            pinnedHost = webView.url?.host?.lowercased()
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !isInitialLoadFinished else { return }
            pinnedHost = webView.url?.host?.lowercased()
            isInitialLoadFinished = true
        }

        private static func isWebURL(_ url: URL) -> Bool {
            let scheme = url.scheme?.lowercased()
            return scheme == "http" || scheme == "https"
        }

        /// Cùng host, hoặc host con/cha của nhau (`www.a.com` ↔ `a.com`, `player.a.com` ↔ `a.com`).
        /// Không có host ghim (HTML nạp không `baseURL`) ⇒ mọi điều hướng http(s) của khung chính đều bị chặn.
        private static func host(_ candidate: String?, isWithin pinned: String?) -> Bool {
            guard let candidate = candidate?.lowercased(), let pinned, !pinned.isEmpty else { return false }
            return candidate == pinned || candidate.hasSuffix("." + pinned) || pinned.hasSuffix("." + candidate)
        }
    }
}
