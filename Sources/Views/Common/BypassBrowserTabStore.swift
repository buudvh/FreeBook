import Combine
import Foundation
import WebKit

/// Chủ sở hữu duy nhất danh sách tab của trình duyệt bypass, đồng thời là
/// `WKNavigationDelegate` + `WKUIDelegate` dùng chung cho mọi tab.
///
/// Đây là nơi duy nhất tạo/xoá `WKWebView` của trình duyệt bypass: link mở tab
/// mới (`target="_blank"`, `window.open`) đi qua `createWebViewWith` và bắt buộc
/// dùng lại `WKWebViewConfiguration` do WebKit trao — tạo config mới sẽ làm
/// `window.opener` mất liên kết và trang không nạp.
final class BypassBrowserTabStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    /// Trần số tab: mỗi tab là một `WKWebView` nên phải chặn để không phình bộ nhớ.
    static let maxTabCount = 8

    @Published private(set) var tabs: [BypassBrowserTab] = []
    @Published private(set) var activeTabId: String = ""

    /// Chuyển tiếp thay đổi của từng tab lên store để View chỉ cần quan sát store.
    private var tabObservations: [String: AnyCancellable] = [:]

    /// Tab đang hiển thị; rơi về tab đầu nếu `activeTabId` lệch.
    var activeTab: BypassBrowserTab? {
        tabs.first { $0.id == activeTabId } ?? tabs.first
    }

    var canOpenMoreTabs: Bool { tabs.count < Self.maxTabCount }

    deinit {
        for tab in tabs {
            tab.stopLoadingAndDetach()
        }
    }

    /// Tạo tab đầu tiên (nếu chưa có) với URL khởi tạo của trình duyệt.
    @discardableResult
    func prepareFirstTab(url: URL?) -> BypassBrowserTab {
        if let existing = tabs.first {
            return existing
        }
        let tab = makeTab(configuration: nil, url: url)
        tabs = [tab]
        activeTabId = tab.id
        return tab
    }

    /// Mở tab mới. `configuration` khác `nil` khi WebKit yêu cầu mở cửa sổ mới.
    /// Trả `nil` khi đã đạt trần tab.
    @discardableResult
    func openTab(
        url: URL? = nil,
        configuration: WKWebViewConfiguration? = nil,
        activate: Bool = true
    ) -> BypassBrowserTab? {
        guard canOpenMoreTabs else { return nil }
        let tab = makeTab(configuration: configuration, url: url)
        tabs.append(tab)
        if activate {
            activeTabId = tab.id
        }
        return tab
    }

    func select(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
    }

    func closeTab(id: String) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let closing = tabs[index]
        tabs.remove(at: index)
        tabObservations.removeValue(forKey: id)
        closing.stopLoadingAndDetach()

        if activeTabId == id {
            let fallbackIndex = min(index, tabs.count - 1)
            activeTabId = tabs[fallbackIndex].id
        }
    }

    // MARK: - Tab factory

    private func makeTab(configuration: WKWebViewConfiguration?, url: URL?) -> BypassBrowserTab {
        let config = configuration ?? makeDefaultConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let tab = BypassBrowserTab(webView: webView, initialUrl: url)
        tabObservations[tab.id] = tab.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        return tab
    }

    private func makeDefaultConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        // Cho phép trang tự gọi `window.open` (nhiều nguồn truyện dùng để mở link ngoài).
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        return config
    }

    private func tab(for webView: WKWebView) -> BypassBrowserTab? {
        tabs.first { $0.webView === webView }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if let url = navigationAction.request.url, isEngineDomainBlocked(url.absoluteString) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    // MARK: - WKUIDelegate

    /// Link `target="_blank"` / `window.open`: mở tab mới và trả webView cho
    /// WebKit tự nạp request. Không tự `load` — WebKit sẽ nạp giúp.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let newTab = openTab(configuration: configuration, activate: true) {
            AppLogger.shared.log("[BypassBrowser] Mở tab mới cho link ngoài (\(tabs.count)/\(Self.maxTabCount))")
            return newTab.webView
        }

        // Đã đạt trần tab: nạp ngay trên tab hiện tại để không mất link.
        if let url = navigationAction.request.url {
            AppLogger.shared.log("[BypassBrowser] Đạt trần \(Self.maxTabCount) tab — nạp link ngoài trên tab hiện tại")
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {
        guard let tab = tab(for: webView) else { return }
        closeTab(id: tab.id)
    }
}
