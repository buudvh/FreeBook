import SwiftUI
import WebKit

/// WebView **hiển thị** cho kế hoạch `.embed` (track `webview` không bắt được link media):
/// nhúng nguyên trang xem để người dùng bấm play trong trang. Không có timeSkip, phụ đề hay lưu giây.
///
/// `updateUIView` chạy theo mỗi lần màn cha vẽ lại ⇒ so với nội dung đã nạp trong Coordinator,
/// chỉ nạp lại khi thật sự đổi trang.
struct VideoEmbedWebView: UIViewRepresentable {
    let content: VideoPlayerController.EmbedContent

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
        context.coordinator.load(content, into: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(content, into: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // Dừng hẳn media của trang; nếu không, tiếng phim còn chạy sau khi rời màn.
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
        coordinator.reset()
    }

    final class Coordinator {
        private var loadedContent: VideoPlayerController.EmbedContent?

        func load(_ content: VideoPlayerController.EmbedContent, into webView: WKWebView) {
            guard loadedContent != content else { return }
            loadedContent = content
            switch content {
            case .page(let url):
                webView.load(URLRequest(url: url))
            case .html(let html, let baseURL):
                webView.loadHTMLString(html, baseURL: baseURL)
            }
        }

        func reset() {
            loadedContent = nil
        }
    }
}
