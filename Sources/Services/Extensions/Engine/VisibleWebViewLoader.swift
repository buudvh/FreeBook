import Foundation
import UIKit
import WebKit

// MARK: - Visible WKWebView Controller & Loader Helper
public final class VisibleWebViewController: UIViewController, WKNavigationDelegate {
    let webView: WKWebView
    private let titleString: String
    var onDismiss: (() -> Void)?
    
    fileprivate var navigationCompletion: ((String?) -> Void)?
    fileprivate var waitUrlCompletion: ((Bool) -> Void)?
    fileprivate var targetUrlToWait: String?

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

    @objc private func handleClose() {
        onDismiss?()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            if isEngineDomainBlocked(urlString) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    private func checkWaitUrl(_ currentUrl: String?) {
        guard let current = currentUrl, let target = targetUrlToWait, let comp = waitUrlCompletion else { return }
        if current.contains(target) {
            self.waitUrlCompletion = nil
            self.targetUrlToWait = nil
            comp(true)
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

class VisibleWebViewLoader: NSObject, UIAdaptivePresentationControllerDelegate {
    let viewController: VisibleWebViewController
    private var navController: UINavigationController?
    private var isPresented = false
    private var isCleaningUp = false
    var onClose: (() -> Void)?

    private var waitForReadyCompletion: ((String) -> Void)?
    private var isWaitingForReady = false
    private var waitReadyTimerWorkItem: DispatchWorkItem?
    private var waitReadyTimeoutWorkItem: DispatchWorkItem?

    init(title: String) {
        self.viewController = VisibleWebViewController(title: title)
        super.init()
        self.viewController.onDismiss = { [weak self] in
            self?.cleanUp()
        }
    }

    deinit {
        cleanUp()
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        self.isPresented = false
        self.cleanUp()
    }

    func cancelPendingWaitReady(reason: String, cancelled: Bool) {
        waitReadyTimerWorkItem?.cancel()
        waitReadyTimerWorkItem = nil
        waitReadyTimeoutWorkItem?.cancel()
        waitReadyTimeoutWorkItem = nil

        if isWaitingForReady {
            isWaitingForReady = false
            if let comp = waitForReadyCompletion {
                waitForReadyCompletion = nil
                let json = makeReadyResponse(ready: false, failed: true, reason: reason, cancelled: cancelled)
                comp(json)
            }
        }
    }

    func cleanUp() {
        if Thread.isMainThread {
            guard !isCleaningUp else { return }
            isCleaningUp = true

            self.viewController.webView.navigationDelegate = nil
            self.viewController.webView.stopLoading()
            self.viewController.navigationCompletion = nil
            self.viewController.waitUrlCompletion = nil
            self.cancelPendingWaitReady(reason: "Browser closed/cleaned up", cancelled: true)
            if isPresented, let nav = navController {
                isPresented = false
                nav.dismiss(animated: true, completion: nil)
            }

            let callback = onClose
            onClose = nil
            callback?()
        } else {
            DispatchQueue.main.async {
                self.cleanUp()
            }
        }
    }

    @MainActor
    private func presentUIIfNeeded() {
        guard !isPresented else { return }
        
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootVC = windowScene.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        let nav = UINavigationController(rootViewController: viewController)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        self.navController = nav
        self.isPresented = true
        topVC.present(nav, animated: true, completion: nil)
    }

    func load(url: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.viewController.navigationCompletion = completion
        let request = URLRequest(url: url)

        DispatchQueue.main.async {
            self.presentUIIfNeeded()
            self.viewController.webView.load(request)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.viewController.navigationCompletion else { return }
            self.viewController.navigationCompletion = nil
            self.viewController.webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                comp(html as? String ?? "")
            }
        }
    }

    func getHtml(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            self.viewController.webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                completion(html as? String ?? "")
            }
        }
    }

    func callJs(script: String, waitTime: TimeInterval, completion: @escaping (String?, Error?) -> Void) {
        DispatchQueue.main.async {
            self.viewController.webView.evaluateJavaScript(script) { result, error in
                let resStr = (result != nil) ? String(describing: result!) : ""
                if waitTime > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + waitTime) {
                        completion(resStr, error)
                    }
                } else {
                    completion(resStr, error)
                }
            }
        }
    }

    func waitUrl(targetUrl: String, timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        self.viewController.targetUrlToWait = targetUrl
        self.viewController.waitUrlCompletion = completion

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.viewController.waitUrlCompletion else { return }
            self.viewController.waitUrlCompletion = nil
            self.viewController.targetUrlToWait = nil
            comp(false)
        }
    }

    func waitForReady(
        probeScript: String,
        timeoutMs: Double,
        intervalMs: Double,
        stablePasses: Int,
        completion: @escaping (String) -> Void
    ) {
        if isWaitingForReady {
            cancelPendingWaitReady(reason: "Cancelled by a new waitForReady request", cancelled: true)
        }

        isWaitingForReady = true
        waitForReadyCompletion = completion

        let clampedTimeout = max(1.0, min(60.0, timeoutMs / 1000.0))
        let clampedInterval = max(0.1, min(2.0, intervalMs / 1000.0))
        let clampedStablePasses = max(1, min(5, stablePasses))

        if probeScript.count > 16384 {
            let errorJson = makeReadyResponse(ready: false, failed: true, reason: "probeScript length exceeded 16 KiB limit")
            isWaitingForReady = false
            waitForReadyCompletion = nil
            completion(errorJson)
            return
        }

        var stableCount = 0
        var lastChars = -1
        var lastEncoded = -1

        let timeoutItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            if self.isWaitingForReady {
                self.waitReadyTimerWorkItem?.cancel()
                self.waitReadyTimerWorkItem = nil
                if let comp = self.waitForReadyCompletion {
                    self.waitForReadyCompletion = nil
                    self.isWaitingForReady = false
                    let response = makeReadyResponse(ready: false, failed: true, reason: "Timeout reached during wait", timedOut: true)
                    comp(response)
                }
            }
        }
        self.waitReadyTimeoutWorkItem = timeoutItem
        DispatchQueue.main.asyncAfter(deadline: .now() + clampedTimeout, execute: timeoutItem)

        func pollNext() {
            guard self.isWaitingForReady else { return }

            self.viewController.webView.evaluateJavaScript(probeScript) { [weak self] result, error in
                guard let self = self, self.isWaitingForReady else { return }

                if let error = error {
                    self.cancelPendingWaitReady(reason: "evaluateJavaScript error: \(error.localizedDescription)", cancelled: false)
                    return
                }

                guard let resultStr = result as? String else {
                    self.cancelPendingWaitReady(reason: "probeScript returned non-string result", cancelled: false)
                    return
                }

                guard let data = resultStr.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.cancelPendingWaitReady(reason: "Failed to parse probeScript JSON response", cancelled: false)
                    return
                }

                let failed = json["failed"] as? Bool ?? false
                if failed {
                    let reason = json["reason"] as? String ?? "Probe script reported failure"
                    self.cancelPendingWaitReady(reason: reason, cancelled: false)
                    return
                }

                let ready = json["ready"] as? Bool ?? false
                let chars = json["chars"] as? Int ?? 0
                let encoded = json["encoded"] as? Int ?? 0

                if ready {
                    if chars == lastChars && encoded == lastEncoded {
                        stableCount += 1
                    } else {
                        stableCount = 1
                        lastChars = chars
                        lastEncoded = encoded
                    }

                    if stableCount >= clampedStablePasses {
                        self.waitReadyTimeoutWorkItem?.cancel()
                        self.waitReadyTimeoutWorkItem = nil
                        if let comp = self.waitForReadyCompletion {
                            self.waitForReadyCompletion = nil
                            self.isWaitingForReady = false
                            let response = makeReadyResponse(ready: true, failed: false, reason: "", chars: chars, encoded: encoded)
                            comp(response)
                        }
                        return
                    }
                } else {
                    stableCount = 0
                    lastChars = -1
                    lastEncoded = -1
                }

                let timerItem = DispatchWorkItem {
                    pollNext()
                }
                self.waitReadyTimerWorkItem = timerItem
                DispatchQueue.main.asyncAfter(deadline: .now() + clampedInterval, execute: timerItem)
            }
        }

        pollNext()
    }
}
