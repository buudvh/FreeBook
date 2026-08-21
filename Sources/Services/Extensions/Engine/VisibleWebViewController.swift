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

    init(title: String) {
        self.titleString = title
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all
        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init(nibName: nil, bundle: nil)
        self.webView.navigationDelegate = self
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
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

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            if interceptedUrls.count >= 200 {
                interceptedUrls.removeFirst()
            }
            interceptedUrls.append(urlString)

            if isEngineDomainBlocked(urlString) || isDynamicDomainBlocked(urlString) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    internal func checkWaitUrl(_ currentUrl: String?) {
        guard let current = currentUrl, let targets = targetUrlsToWait, let comp = waitUrlCompletion else { return }
        for target in targets {
            if current.contains(target) {
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
        checkWaitUrl(webView.url?.absoluteString)
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        checkWaitUrl(webView.url?.absoluteString)
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
