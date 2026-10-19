import Foundation
import UIKit
import WebKit

// MARK: - Visible WKWebView Controller & Loader Helper
public final class VisibleWebViewController: UIViewController, WKNavigationDelegate {
    let webView: WKWebView
    let titleString: String
    var onDismiss: (() -> Void)?
    
    public private(set) var interceptedUrls: [String] = []
    internal var dynamicBlockedPatterns: [String] = []
    internal var navigationCompletion: ((String?) -> Void)?
    internal var waitUrlCompletion: ((Bool) -> Void)?
    internal var targetUrlsToWait: [String]?
    /// Trần `interceptedUrls` (bỏ URL cũ nhất khi đầy); nâng từ 200 vì giờ chứa cả request XHR/fetch/media.
    internal static let maxRecordedUrls = 1000
    /// Chặn QC / chế độ máy tính theo tiện ích. Không có tiện ích (đăng nhập Gemini) ⇒ `.excluded`: không luật, UA
    /// iPhone như cũ.
    internal let contentDecision: WebContentDecision
    /// Cổng 11 tên miền (`isEngineDomainBlocked`) ở `decidePolicyFor`: theo chặn QC của tiện ích; không có tiện ích thì
    /// giữ nguyên hành vi cũ (luôn xét) vì webview đăng nhập nằm ngoài phạm vi chặn quảng cáo.
    internal let appliesEngineDomainGate: Bool

    init(title: String, extensionLocalPath: String? = nil) {
        self.titleString = title
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        self.webView = WKWebView(frame: .zero, configuration: config)
        let decision = WebContentPolicy.decision(forExtensionLocalPath: extensionLocalPath)
        self.contentDecision = decision
        self.appliesEngineDomainGate = extensionLocalPath == nil ? true : decision.adBlock
        super.init(nibName: nil, bundle: nil)
        FileDescriptorCensus.trackLive("VisibleWebView", 1)
        self.webView.navigationDelegate = self
        WebContentConfigurator.apply(decision, to: webView)  // luật chặn QC + UA (mobile/desktop)
        // Browser hiện của ext không autoplay (giữ `.all`), chỉ bắt request cho `urls()` / `waitUrl`.
        WebNetworkCaptureScript.install(into: webView.configuration.userContentController, mediaMode: false) { [weak self] url, _ in
            self?.recordCapturedRequest(url)
        }
    }

    deinit {
        FileDescriptorCensus.trackLive("VisibleWebView", -1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = titleString.isEmpty ? "Trình duyệt" : titleString

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Đóng",
            style: .done,
            target: self,
            action: #selector(handleClose)
        )

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    @objc internal func handleClose() {
        onDismiss?()
    }

    public func isDynamicDomainBlocked(_ urlString: String) -> Bool {
        let lower = urlString.lowercased()
        for pattern in dynamicBlockedPatterns {
            if lower.contains(pattern.lowercased()) {
                return true
            }
        }
        return false
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == true {
            preferences.preferredContentMode = WebContentConfigurator.contentMode(for: contentDecision)
        }
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            if interceptedUrls.count >= Self.maxRecordedUrls {
                interceptedUrls.removeFirst()
            }
            interceptedUrls.append(urlString)

            // Luật script tiện ích khai (`Engine.block`) luôn xét; mọi khung dùng chung decision của browser.
            if (appliesEngineDomainGate && isEngineDomainBlocked(urlString)) || isDynamicDomainBlocked(urlString) {
                decisionHandler(.cancel, preferences)
                return
            }
            checkWaitUrl(urlString, allowSubstring: true)  // cả điều hướng iframe
        }
        decisionHandler(.allow, preferences)
    }

    /// Request XHR/fetch/media do `WebNetworkCaptureScript` báo về: gộp vào `interceptedUrls` (không trùng) để
    /// `urls()` / `waitUrl` thấy đúng hợp đồng extension. Khác browser ẩn: không reset theo launch và `waitUrl` không xét URL đã có
    /// từ trước (mốc launch nằm ở `VisibleWebViewLoader`; xét URL cũ dễ khớp nhầm, vd. trang login chuyển hướng).
    internal func recordCapturedRequest(_ url: String) {
        guard WebNetworkCaptureScript.isRecordable(url),
              !isEngineDomainBlocked(url),
              !isDynamicDomainBlocked(url) else { return }
        if !interceptedUrls.contains(url) {
            if interceptedUrls.count >= Self.maxRecordedUrls {
                interceptedUrls.removeFirst()
            }
            interceptedUrls.append(url)
        }
        // Request bắt được chỉ khớp regex toàn URL (không khớp chuỗi con) — xem `WebNetworkCaptureScript.url`.
        checkWaitUrl(url, allowSubstring: false)
    }

    /// `allowSubstring`: `true` cho URL điều hướng (luật cũ), `false` cho request do script bắt được.
    internal func checkWaitUrl(_ currentUrl: String?, allowSubstring: Bool) {
        guard let current = currentUrl, let targets = targetUrlsToWait, let comp = waitUrlCompletion else { return }
        for target in targets {
            if WebNetworkCaptureScript.url(current, matchesWaitPattern: target, allowSubstring: allowSubstring) {
                self.waitUrlCompletion = nil
                self.targetUrlsToWait = nil
                comp(true)
                break
            }
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let comp = self.navigationCompletion {
            self.navigationCompletion = nil
            webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                comp(html as? String ?? "")
            }
        }
        checkWaitUrl(webView.url?.absoluteString, allowSubstring: true)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        checkWaitUrl(webView.url?.absoluteString, allowSubstring: true)
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let comp = self.navigationCompletion {
            self.navigationCompletion = nil
            comp("")
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let comp = self.navigationCompletion {
            self.navigationCompletion = nil
            comp("")
        }
    }
}
