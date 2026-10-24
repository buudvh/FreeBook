import Foundation
import UIKit
import WebKit

/// Một tab của trình duyệt bypass: sở hữu `WKWebView` riêng và phản chiếu trạng
/// thái hiển thị (tiêu đề, URL, tiến độ nạp, cờ điều hướng) qua KVO.
///
/// Tab nền vẫn tự cập nhật tiêu đề/URL vì observer thuộc chính tab, không thuộc
/// `UIViewRepresentable` — nhờ vậy đổi tab không mất trạng thái.
///
/// User-Agent, luật chặn quảng cáo và chế độ máy tính **không** gán ở đây: `BypassBrowserTabStore` áp qua
/// `WebContentConfigurator` (theo tên miền) ngay khi tạo tab và ở mỗi điều hướng khung chính.
final class BypassBrowserTab: ObservableObject, Identifiable {
    let id: String
    let webView: WKWebView

    @Published var title: String
    @Published var urlString: String
    @Published var isLoading: Bool = false
    @Published var progress: Double = 0.0
    @Published var canGoBack: Bool = false
    @Published var canGoForward: Bool = false
    /// Tab **ẩn danh**: không ghi Lịch sử truy cập. `BypassBrowserTabStore` bật khi khung chính vào trang của nguồn tắt
    /// "Lưu lịch sử đọc/xem" (`BrowserSourceSiteIndex`); giữ tới khi về Home / mở tab mới, tab mở từ nó thừa hưởng.
    @Published var isIncognito: Bool = false

    /// Trạng thái luật/UA/chế độ hiển thị đã áp lên `webView` lần gần nhất (`nil` = chưa áp hoặc đã mất hiệu lực vì
    /// tab khác dùng chung `WKUserContentController` vừa đổi luật). Không `@Published`: View không vẽ theo nó.
    var appliedState: WebContentAppliedState?
    /// Rule list (định danh đối tượng) gắn ở lần áp gần nhất. Bộ lọc biên dịch xong muộn / bật-tắt / cập nhật làm bộ
    /// này lệch ⇒ điều hướng khung chính kế tiếp gắn lại (không huỷ + nạp lại), vì `appliedState` không đổi.
    var appliedRuleListIds: [ObjectIdentifier] = []
    /// Chống lặp cancel + nạp lại (R1): URL tab vừa tự nạp lại sau khi phải đổi luật/UA. Còn giá trị ⇒ chuỗi điều
    /// hướng hiện tại đã dùng lượt cancel duy nhất, mọi điều hướng khung chính tiếp theo (kể cả chuyển hướng của
    /// server) chỉ áp rồi cho qua. Xoá khi trang commit hoặc lỗi tải.
    var policyReloadURL: URL?

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
