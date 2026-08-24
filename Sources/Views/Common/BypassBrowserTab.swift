import Foundation
import UIKit
import WebKit

/// Một tab của trình duyệt bypass: sở hữu `WKWebView` riêng và phản chiếu trạng
/// thái hiển thị (tiêu đề, URL, tiến độ nạp, cờ điều hướng) qua KVO.
///
/// Tab nền vẫn tự cập nhật tiêu đề/URL vì observer thuộc chính tab, không thuộc
/// `UIViewRepresentable` — nhờ vậy đổi tab không mất trạng thái.
final class BypassBrowserTab: ObservableObject, Identifiable {
    static let mobileUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    let id: String
    let webView: WKWebView

    @Published var title: String
    @Published var urlString: String
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false

    /// URL cần nạp khi tab được hiển thị lần đầu. `nil` với tab do WebKit tự nạp
    /// (`window.open` / `target="_blank"`) — nạp lại tay sẽ làm hỏng navigation.
    private var pendingUrl: URL?
    private var observers: [NSKeyValueObservation] = []

    init(
        id: String = UUID().uuidString,
        webView: WKWebView,
        initialUrl: URL? = nil,
        title: String = ""
    ) {
        self.id = id
        self.webView = webView
        self.title = title
        self.urlString = initialUrl?.absoluteString ?? ""
        self.pendingUrl = initialUrl
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = Self.mobileUserAgent
        attachObservers()
    }

    deinit {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
    }

    /// Tiêu đề rút gọn cho pill tab.
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let host = URL(string: urlString)?.host, !host.isEmpty { return host }
        return "Trang mới"
    }

    /// Lấy và xoá URL chờ nạp; gọi đúng một lần khi tab lên màn hình.
    func consumePendingUrl() -> URL? {
        let url = pendingUrl
        pendingUrl = nil
        return url
    }

    func load(_ url: URL) {
        pendingUrl = nil
        webView.load(URLRequest(url: url))
    }

    func stopLoadingAndDetach() {
        observers.forEach { $0.invalidate() }
        observers.removeAll()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    private func attachObservers() {
        let loadingObserver = webView.observe(\.isLoading, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.isLoading = webView.isLoading }
        }
        let progressObserver = webView.observe(\.estimatedProgress, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.progress = webView.estimatedProgress }
        }
        let titleObserver = webView.observe(\.title, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                if let webTitle = webView.title, !webTitle.isEmpty {
                    self?.title = webTitle
                }
            }
        }
        let urlObserver = webView.observe(\.url, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async {
                if let webUrl = webView.url?.absoluteString {
                    self?.urlString = webUrl
                }
            }
        }
        let goBackObserver = webView.observe(\.canGoBack, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.canGoBack = webView.canGoBack }
        }
        let goForwardObserver = webView.observe(\.canGoForward, options: .new) { [weak self] webView, _ in
            DispatchQueue.main.async { self?.canGoForward = webView.canGoForward }
        }
        observers = [loadingObserver, progressObserver, titleObserver, urlObserver, goBackObserver, goForwardObserver]
    }
}
