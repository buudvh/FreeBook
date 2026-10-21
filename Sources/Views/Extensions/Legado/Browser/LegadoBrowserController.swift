import Foundation
import WebKit

/// `WKWebView` của **trình duyệt nhỏ nguồn Legado** (spec §10.2 đăng nhập trên web, §10.8 `java.startBrowser*`).
///
/// - Kho dữ liệu `nonPersistent` riêng cho mỗi lần mở: gieo cookie hiện có của nguồn trước khi nạp, lúc đóng đọc lại
///   cookie của **các tên miền đã ghé** (khung chính) — đúng "đồng bộ hai chiều khi mở và khi đóng", không rò cookie sang
///   trình duyệt người dùng hay nguồn khác.
/// - Chặn quảng cáo / chế độ hiển thị theo `WebContentPolicy` của tiện ích (nguồn Legado là một tiện ích); UA = UA nguồn
///   khai (thắng chế độ máy tính, như webview tiện ích JS).
/// - `html` khác `nil` ⇒ nạp chuỗi đó với URL nền = `url`; URL `data:` ⇒ giải bằng `LegadoDataURL` rồi nạp byte.
@MainActor
final class LegadoBrowserController: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    /// Trạng thái trang lúc đóng.
    struct Snapshot {
        let html: String
        let finalURL: String
        let cookies: [HTTPCookie]
    }

    let webView: WKWebView
    @Published private(set) var currentURL: String
    @Published private(set) var isLoading = false
    @Published private(set) var loadError: String?

    private let request: LegadoBrowserRequest
    private let decision: WebContentDecision
    private var visitedHosts: Set<String> = []
    private var didStart = false
    /// Hộp thoại `alert`/`confirm`/`prompt` đang chờ người dùng (WebKit chỉ mở một hộp thoại mỗi lần).
    private var pendingPanel: LegadoBrowserJSPanel?

    init(request: LegadoBrowserRequest) {
        self.request = request
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        webView = WKWebView(frame: .zero, configuration: configuration)
        let packageId = LegadoSourceIdentity.packageId(forSourceUrl: request.sourceKey)
        decision = WebContentPolicy.decision(for: .extensionContent(packageId: packageId))
        currentURL = LegadoDataURL.isDataURL(request.url) ? "" : request.url
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        WebContentConfigurator.apply(decision, to: webView, explicitUserAgent: request.userAgent)
        if let host = URL(string: request.url)?.host?.lowercased() {
            visitedHosts.insert(host)
        }
    }

    /// Gieo cookie của nguồn rồi nạp trang (một lần).
    func start() async {
        guard !didStart else { return }
        didStart = true
        let store = webView.configuration.websiteDataStore.httpCookieStore
        for cookie in request.httpCookies {
            await store.setCookie(cookie)
        }
        load()
    }

    func reload() {
        if webView.url == nil {
            load()
        } else {
            webView.reload()
        }
    }

    /// outerHTML + URL hiện tại + cookie của các tên miền đã ghé. Gọi **trước** khi đóng trình duyệt.
    func snapshot() async -> Snapshot {
        let html: String = await withCheckedContinuation { (continuation: CheckedContinuation<String, Never>) in
            webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''") { value, _ in
                continuation.resume(returning: value as? String ?? "")
            }
        }
        let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
        let hosts = visitedHosts
        let cookies = all.filter { cookie in
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            return !domain.isEmpty && hosts.contains { $0 == domain || $0.hasSuffix("." + domain) }
        }
        let finalURL = webView.url?.absoluteString ?? request.url
        return Snapshot(html: html, finalURL: finalURL, cookies: cookies)
    }

    /// Dừng tải và gỡ delegate (trình duyệt đã đóng). Hộp thoại JS còn chờ ⇒ trả mặc định để trang không treo.
    func tearDown() {
        pendingPanel?.cancel()
        pendingPanel = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    // MARK: - Nạp

    private func load() {
        loadError = nil
        if let html = request.html {
            webView.loadHTMLString(html, baseURL: URL(string: request.url))
            return
        }
        if let decoded = LegadoDataURL.decode(request.url) {
            let mime = decoded.mime.trimmingCharacters(in: .whitespaces)
            webView.load(decoded.bytes, mimeType: mime.isEmpty ? "text/html" : mime,
                         characterEncodingName: "utf-8", baseURL: URL(string: "about:blank")!)
            return
        }
        guard let url = Self.makeURL(request.url) else {
            loadError = "Địa chỉ không hợp lệ."
            return
        }
        var urlRequest = URLRequest(url: url)
        for (name, value) in request.headers {
            let lower = name.lowercased()
            // UA đặt qua `customUserAgent`, cookie đã gieo vào kho — không gửi trùng.
            guard lower != "user-agent", lower != "cookie" else { continue }
            urlRequest.setValue(value, forHTTPHeaderField: name)
        }
        webView.load(urlRequest)
    }

    private static func makeURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), url.scheme != nil { return url }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: encoded)
    }

    private func refreshURL() {
        if let url = webView.url, url.scheme?.lowercased() != "about" {
            currentURL = url.absoluteString
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true {
            preferences.preferredContentMode = WebContentConfigurator.contentMode(for: decision)
            if let host = navigationAction.request.url?.host?.lowercased() {
                visitedHosts.insert(host)
            }
        }
        if decision.adBlock, let url = navigationAction.request.url, isEngineDomainBlocked(url.absoluteString) {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        loadError = nil
        refreshURL()
    }

    func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let host = webView.url?.host?.lowercased() {
            visitedHosts.insert(host)
        }
        refreshURL()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        refreshURL()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        refreshURL()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        isLoading = false
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        isLoading = false
        let nsError = error as NSError
        // Huỷ do điều hướng mới / chặn quảng cáo không phải lỗi người dùng cần thấy.
        if nsError.code != NSURLErrorCancelled, nsError.code != 102 {
            loadError = error.localizedDescription
        }
    }

    // MARK: - WKUIDelegate

    /// Liên kết `target="_blank"` / `window.open` (trang đăng nhập OAuth hay dùng): mở ngay trong trình duyệt này.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - Hộp thoại JS (`alert` / `confirm` / `prompt`)

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        showPanel(.alert, message: message, frame: frame) { _, _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        showPanel(.confirm, message: message, frame: frame) { confirmed, _ in completionHandler(confirmed) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        showPanel(.prompt(defaultText: defaultText), message: prompt, frame: frame) { confirmed, text in
            completionHandler(confirmed ? (text ?? "") : nil)
        }
    }

    /// Mỗi hộp thoại trả completion **đúng một lần** (`LegadoBrowserJSPanel`); tiêu đề = tên miền của khung gọi.
    private func showPanel(_ kind: LegadoBrowserJSPanel.Kind, message: String, frame: WKFrameInfo,
                           reply: @escaping (Bool, String?) -> Void) {
        pendingPanel?.cancel()
        let panel = LegadoBrowserJSPanel { [weak self] confirmed, text in
            reply(confirmed, text)
            self?.pendingPanel = nil
        }
        pendingPanel = panel
        let host = frame.securityOrigin.host
        let fallback = request.sourceName.isEmpty ? "Trang web" : request.sourceName
        panel.present(kind, title: host.isEmpty ? fallback : host, message: message, over: webView)
    }
}
