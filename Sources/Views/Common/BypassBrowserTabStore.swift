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
///
/// Chặn quảng cáo + chế độ máy tính theo tên miền (`WebContentPolicy.decision(for: .userBrowser(host:))`) áp khi tạo
/// tab và ở mỗi điều hướng khung chính; chặn cửa sổ bật lên ở `createWebViewWith` (`blockedPopup`). Ẩn danh
/// (`BypassBrowserTab.isIncognito`) chỉ bỏ ghi Lịch sử truy cập — cookie vẫn ở kho WebKit mặc định, dùng chung với
/// trình duyệt ẩn của tiện ích, để vượt Cloudflare/đăng nhập ở đây vẫn có tác dụng cho nguồn.
final class BypassBrowserTabStore: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    /// Trần số tab: mỗi tab là một `WKWebView` nên phải chặn để không phình bộ nhớ.
    static let maxTabCount = 8

    @Published private(set) var tabs: [BypassBrowserTab] = []
    @Published private(set) var activeTabId: String = ""
    /// Cửa sổ bật lên vừa bị chặn (dải báo đọc giá trị này); `nil` = không có gì để báo.
    @Published private(set) var blockedPopup: BypassBrowserBlockedPopup?

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
        let tab = makeTab(configuration: nil, url: url, policyHost: url?.host)
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
        insertTab(url: url, configuration: configuration, policyHost: url?.host, activate: activate)
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

    // MARK: - Chặn quảng cáo, chế độ máy tính, cửa sổ bật lên (API cho View)

    /// Decision theo tên miền của trang tab đang hiển thị; `nil` khi tab là Home / `about:blank` / chưa có trang.
    func decision(for tab: BypassBrowserTab) -> WebContentDecision? {
        guard let host = Self.pageHost(of: tab) else { return nil }
        return WebContentPolicy.decision(for: .userBrowser(host: host))
    }

    /// Sau khi đổi cài đặt theo tên miền (menu khiên): tính lại decision theo host tab đang xem, áp rồi nạp lại ngay.
    func reloadActiveTabApplyingSitePreferences() {
        guard let tab = activeTab, let decision = self.decision(for: tab) else { return }
        applyContentPolicy(decision, to: tab)
        if tab.webView.url != nil {
            tab.webView.reload()
        } else if let url = URL(string: tab.urlString) {
            tab.load(url)
        }
    }

    func dismissBlockedPopup() {
        blockedPopup = nil
    }

    /// Nút "Mở" của dải báo: mở URL đã chặn ở tab mới (đạt trần tab ⇒ nạp trên tab đang xem) và xoá dải báo.
    func openBlockedPopup() {
        guard let popup = blockedPopup else { return }
        blockedPopup = nil
        guard let url = popup.url else { return }
        let openerIsIncognito = activeTab?.isIncognito ?? false
        if let tab = openTab(url: url, activate: true) {
            tab.isIncognito = openerIsIncognito
            // Không ai tiêu thụ `pendingUrl` của tab không phải tab đầu ⇒ tự nạp.
            tab.load(url)
        } else if let active = activeTab {
            AppLogger.shared.log("[BypassBrowser] Đạt trần \(Self.maxTabCount) tab — mở cửa sổ đã chặn trên tab hiện tại")
            active.load(url)
        }
    }

    // MARK: - Tab factory

    private func insertTab(
        url: URL?,
        configuration: WKWebViewConfiguration?,
        policyHost: String?,
        activate: Bool
    ) -> BypassBrowserTab? {
        guard canOpenMoreTabs else { return nil }
        let tab = makeTab(configuration: configuration, url: url, policyHost: policyHost)
        tabs.append(tab)
        if activate {
            activeTabId = tab.id
        }
        return tab
    }

    /// `policyHost`: host trang sắp nạp (URL đầu, hoặc host đích của cửa sổ mới). `nil` (Home, tab mới) vẫn áp theo
    /// mặc định chung để tab có UA/luật ngay từ đầu, không rơi về UA mặc định của WebKit.
    private func makeTab(configuration: WKWebViewConfiguration?, url: URL?, policyHost: String?) -> BypassBrowserTab {
        let config = configuration ?? makeDefaultConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        let tab = BypassBrowserTab(webView: webView, initialUrl: url)
        applyContentPolicy(WebContentPolicy.decision(for: .userBrowser(host: policyHost)), to: tab)
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

    /// Áp luật/UA lên tab và ghi `appliedState`.
    ///
    /// R1: tab mở qua `createWebViewWith` dùng configuration WebKit trao, rất có thể **chung** `WKUserContentController`
    /// với tab mở nó ⇒ gắn/gỡ luật ở tab này cũng đổi luật của tab kia (UA thì riêng từng webView). Tab chung bộ điều
    /// khiển mà đang tin trạng thái chặn QC khác đi bị đánh dấu chưa áp (`nil`) để tự áp lại ở điều hướng khung chính
    /// kế tiếp của nó. Không tạo được bộ điều khiển riêng (WebKit bắt dùng config trao) ⇒ chấp nhận luật theo tab
    /// vừa điều hướng.
    private func applyContentPolicy(_ decision: WebContentDecision, to tab: BypassBrowserTab) {
        let applied = WebContentConfigurator.apply(decision, to: tab.webView)
        tab.appliedState = applied
        tab.appliedRuleListIds = decision.adBlock ? Self.currentRuleListIds() : []
        let controller = tab.webView.configuration.userContentController
        for other in tabs where other !== tab
            && other.webView.configuration.userContentController === controller
            && other.appliedState?.adBlock != applied.adBlock {
            other.appliedState = nil
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences)
            return
        }
        let owner = self.tab(for: webView)
        guard navigationAction.targetFrame?.isMainFrame == true, let tab = owner, Self.isWebURL(url) else {
            // Khung con, bước trước `createWebViewWith` (`targetFrame == nil`) hoặc URL không phải web: chỉ xét cổng
            // 11 tên miền theo decision đã áp cho khung chính của tab — không tính theo host của iframe, để trang được
            // miễn trừ thì iframe quảng cáo bên trong cũng không bị huỷ. Không bao giờ huỷ + nạp lại ở đây.
            let adBlock = owner?.appliedState?.adBlock
                ?? WebContentPolicy.decision(for: .userBrowser(host: webView.url?.host)).adBlock
            if adBlock, isEngineDomainBlocked(url.absoluteString) {
                decisionHandler(.cancel, preferences)
                return
            }
            decisionHandler(.allow, preferences)
            return
        }
        markIncognitoIfNeeded(tab, url: url) // cả bước chuyển hướng: trang nguồn chuyển sang mirror vẫn ẩn danh
        decideMainFrame(navigationAction, url: url, tab: tab, preferences: preferences, decisionHandler: decisionHandler)
    }

    /// Ẩn danh dính theo tab: ở đây chỉ bật, `BypassWebView` tắt khi về Home. Không ghi host vào log.
    private func markIncognitoIfNeeded(_ tab: BypassBrowserTab, url: URL) {
        guard !tab.isIncognito, BrowserSourceSiteIndex.isPrivate(url: url) else { return }
        tab.isIncognito = true
        AppLogger.shared.log("[BypassBrowser] Trang thuộc nguồn không lưu lịch sử ⇒ tab chuyển sang ẩn danh")
    }

    /// Khung chính: decision theo host đích, cổng 11 tên miền chỉ khi chặn QC bật, đặt chế độ hiển thị.
    ///
    /// R1 (**UNKNOWN**, cần kiểm trên máy — plan §8 K4/K5): đổi `WKContentRuleList`/UA ngay trong `decidePolicyFor`
    /// có kịp hiệu lực cho chính lượt điều hướng đó hay không thì chưa chắc. Vì vậy khi trạng thái **vừa phải đổi** với
    /// điều hướng do link/gõ địa chỉ/script (`.linkActivated`/`.other`, GET) ⇒ áp, huỷ, rồi tự nạp lại request ở vòng
    /// runloop sau để lượt nạp mới chắc chắn chạy với luật/UA mới. Lùi/tiến, tải lại, gửi form ⇒ áp và cho qua (nạp
    /// lại sẽ mất vị trí lịch sử / dữ liệu form). Chống lặp: chỉ khung chính, tối đa một lần mỗi chuỗi điều hướng, lượt
    /// nạp lại do tab tự phát (kể cả chuyển hướng sau đó) luôn được cho qua — xem `BypassBrowserTab.policyReloadURL`.
    private func decideMainFrame(
        _ navigationAction: WKNavigationAction,
        url: URL,
        tab: BypassBrowserTab,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        let decision = WebContentPolicy.decision(for: .userBrowser(host: url.host))
        preferences.preferredContentMode = WebContentConfigurator.contentMode(for: decision)
        if decision.adBlock, isEngineDomainBlocked(url.absoluteString) {
            decisionHandler(.cancel, preferences)
            return
        }
        guard WebContentConfigurator.state(for: decision) != tab.appliedState else {
            // Tab sống lâu: rule list đổi sau lần áp trước (bản đóng gói biên dịch xong, bật/tắt/cập nhật bộ lọc) ⇒ gắn
            // lại cho lượt nạp này/kế tiếp, không huỷ.
            if decision.adBlock, tab.appliedRuleListIds != Self.currentRuleListIds() {
                applyContentPolicy(decision, to: tab)
            }
            decisionHandler(.allow, preferences)
            return
        }
        applyContentPolicy(decision, to: tab)

        let type = navigationAction.navigationType
        let request = navigationAction.request
        let isReplayable = tab.policyReloadURL == nil
            && (type == .linkActivated || type == .other)
            && (request.httpMethod ?? "GET").uppercased() == "GET"
        guard isReplayable else {
            decisionHandler(.allow, preferences)
            return
        }
        decisionHandler(.cancel, preferences)
        AppLogger.shared.log("[BypassBrowser] Đổi luật/UA cho \(url.host ?? "?") ⇒ huỷ và nạp lại trang")
        DispatchQueue.main.async { [weak self, weak tab] in
            guard let self, let tab, self.tabs.contains(where: { $0 === tab }) else { return }
            // Đặt mốc ngay trước khi nạp (không đặt lúc huỷ): báo lỗi của lượt vừa huỷ không được xoá mốc của lượt mới.
            tab.policyReloadURL = request.url
            tab.webView.load(request)
        }
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        tab(for: webView)?.policyReloadURL = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let tab = self.tab(for: webView)
        tab?.policyReloadURL = nil
        guard let url = webView.url, !url.absoluteString.isEmpty, url.absoluteString != "about:blank" else { return }
        // Trang khôi phục từ bộ đệm lùi/tiến có thể không qua `decidePolicyFor` ⇒ xét lại ẩn danh trước khi ghi.
        if let tab {
            markIncognitoIfNeeded(tab, url: url)
            guard !tab.isIncognito else { return }
        } else if BrowserSourceSiteIndex.isPrivate(url: url) {
            return
        }
        BrowserHistoryStore.shared.add(title: webView.title ?? "", urlString: url.absoluteString)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        clearPolicyReloadMarker(for: webView, after: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        clearPolicyReloadMarker(for: webView, after: error)
    }

    /// Bỏ qua huỷ điều hướng (-999) và điều hướng bị policy chặn (WebKit 102): đó thường là lượt vừa bị chính
    /// `decideMainFrame` huỷ, xoá mốc lúc này sẽ mở lại đường nảy vô hạn.
    private func clearPolicyReloadMarker(for webView: WKWebView, after error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        tab(for: webView)?.policyReloadURL = nil
    }

    // MARK: - WKUIDelegate

    /// Link `target="_blank"` / `window.open`: mở tab mới và trả webView cho
    /// WebKit tự nạp request. Không tự `load` — WebKit sẽ nạp giúp.
    ///
    /// Chặn cửa sổ bật lên (công tắc chung, chỉ trình duyệt này): cửa sổ **không** do người dùng bấm link
    /// (`navigationType != .linkActivated`) mở sang tên miền khác trang đang xem — hoặc cửa sổ trống — bị chặn và báo
    /// qua `blockedPopup`. Link `_blank` người dùng bấm vẫn mở tab như cũ.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let target = Self.webTarget(of: navigationAction.request.url)
        if shouldBlockPopup(navigationAction, target: target, openerHost: webView.url?.host) {
            blockedPopup = BypassBrowserBlockedPopup(url: target, host: target?.host)
            AppLogger.shared.log("[BypassBrowser] Chặn cửa sổ bật lên: \(target?.host ?? "(cửa sổ trống)")")
            return nil
        }

        if let newTab = insertTab(url: nil, configuration: configuration, policyHost: target?.host, activate: true) {
            newTab.isIncognito = tab(for: webView)?.isIncognito ?? false
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

    // MARK: - Helpers

    /// So với host **khung chính** của trang mở (không theo `sourceFrame`): iframe quảng cáo gọi `window.open` sang
    /// chính tên miền của nó vẫn bị tính là khác tên miền trang.
    private func shouldBlockPopup(_ navigationAction: WKNavigationAction, target: URL?, openerHost: String?) -> Bool {
        guard WebContentSettings.popupBlockingEnabled,
              navigationAction.navigationType != .linkActivated else { return false }
        guard let targetHost = target?.host else { return true }
        return !Self.isSameSite(targetHost, openerHost)
    }

    /// Cùng host, hoặc host con/cha của nhau sau khi bỏ `www.` (như `VideoEmbedWebView.Coordinator.host(_:isWithin:)`,
    /// thêm chuẩn hoá để `m.a.com` ↔ `www.a.com` là cùng trang).
    private static func isSameSite(_ candidate: String?, _ opener: String?) -> Bool {
        guard let lhs = BrowserSitePreferenceStore.normalizedDomain(for: candidate), !lhs.isEmpty,
              let rhs = BrowserSitePreferenceStore.normalizedDomain(for: opener), !rhs.isEmpty else { return false }
        return lhs == rhs || lhs.hasSuffix("." + rhs) || rhs.hasSuffix("." + lhs)
    }

    /// URL http(s) có host của cửa sổ mới; rỗng, `about:blank`, `data:`, `blob:`… ⇒ `nil` (cửa sổ trống).
    private static func webTarget(of url: URL?) -> URL? {
        guard let url, isWebURL(url), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    /// Host trang tab đang hiển thị; Home / `about:blank` / rỗng / không phải web ⇒ `nil`.
    private static func pageHost(of tab: BypassBrowserTab) -> String? {
        let text = tab.urlString
        guard !text.isEmpty, text != "about:blank", text != "Home",
              let url = URL(string: text), isWebURL(url),
              let host = url.host, !host.isEmpty else { return nil }
        return host
    }

    private static func currentRuleListIds() -> [ObjectIdentifier] {
        AdBlockRuleListProvider.currentRuleLists().map { ObjectIdentifier($0) }
    }

    private static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }
}
