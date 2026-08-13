import Foundation
import WebKit

internal func makeReadyResponse(
    ready: Bool,
    failed: Bool,
    reason: String,
    timedOut: Bool = false,
    cancelled: Bool = false,
    chars: Int = 0,
    encoded: Int = 0
) -> String {
    let dict: [String: Any] = [
        "ready": ready,
        "failed": failed,
        "reason": reason,
        "timedOut": timedOut,
        "cancelled": cancelled,
        "chars": chars,
        "encoded": encoded
    ]
    if let data = try? JSONSerialization.data(withJSONObject: dict),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return "{\"ready\":false,\"failed\":true,\"reason\":\"JSON serialization error\",\"timedOut\":false,\"cancelled\":false}"
}

public func isEngineDomainBlocked(_ urlString: String) -> Bool {
    guard let url = URL(string: urlString), let host = url.host?.lowercased() else {
        return false
    }
    let blockedDomains = [
        "google-analytics.com",
        "doubleclick.net",
        "googlesyndication.com",
        "mgid.com",
        "taboola.com",
        "erodalabs.com",
        "tip-top.one",
        "bet88", "w88", "fun88", "shopee.vn", "lazada.vn"
    ]
    for blocked in blockedDomains {
        if host.contains(blocked) {
            return true
        }
    }
    return false
}

class WebViewLoader: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    internal var completion: ((String?) -> Void)?
    internal var waitUrlCompletion: ((Bool) -> Void)?
    internal var targetUrlToWait: String?

    internal var waitForReadyCompletion: ((String) -> Void)?
    internal var isWaitingForReady = false
    internal var waitReadyTimerWorkItem: DispatchWorkItem?
    internal var waitReadyTimeoutWorkItem: DispatchWorkItem?

    deinit {
        let wv = self.webView
        DispatchQueue.main.async {
            wv.navigationDelegate = nil
            wv.stopLoading()
        }
    }

    internal func cancelPendingWaitReady(reason: String, cancelled: Bool) {
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
            self.webView.navigationDelegate = nil
            self.webView.stopLoading()
            self.completion = nil
            self.waitUrlCompletion = nil
            self.cancelPendingWaitReady(reason: "Browser closed/cleaned up", cancelled: true)
        } else {
            let wv = self.webView
            DispatchQueue.main.async {
                wv.navigationDelegate = nil
                wv.stopLoading()
            }
            self.completion = nil
            self.waitUrlCompletion = nil
            DispatchQueue.main.async {
                self.cancelPendingWaitReady(reason: "Browser closed/cleaned up", cancelled: true)
            }
        }
    }

    override init() {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = .all

        self.webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        self.webView.navigationDelegate = self
        self.webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let url = navigationAction.request.url {
            let urlString = url.absoluteString
            if isEngineDomainBlocked(urlString) {
                decisionHandler(.cancel)
                return
            }
        }
        decisionHandler(.allow)
    }

    func load(url: URL, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.completion = completion
        let request = URLRequest(url: url)

        DispatchQueue.main.async {
            self.webView.load(request)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.completion else { return }
            self.completion = nil
            self.webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                comp(html as? String ?? "")
            }
        }
    }

    func getHtml(completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                completion(html as? String ?? "")
            }
        }
    }

    func callJs(script: String, waitTime: TimeInterval, completion: @escaping (String?, Error?) -> Void) {
        DispatchQueue.main.async {
            self.webView.evaluateJavaScript(script) { result, error in
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
        self.targetUrlToWait = targetUrl
        self.waitUrlCompletion = completion

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.waitUrlCompletion else { return }
            self.waitUrlCompletion = nil
            self.targetUrlToWait = nil
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

            self.webView.evaluateJavaScript(probeScript) { [weak self] result, error in
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

    internal func checkWaitUrl(_ currentUrl: String?) {
        guard let current = currentUrl, let target = targetUrlToWait, let comp = waitUrlCompletion else { return }
        if current.contains(target) {
            self.waitUrlCompletion = nil
            self.targetUrlToWait = nil
            comp(true)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let comp = self.completion {
            self.completion = nil
            webView.evaluateJavaScript("document.documentElement.outerHTML") { html, error in
                comp(html as? String ?? "")
            }
        }
        checkWaitUrl(webView.url?.absoluteString)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        checkWaitUrl(webView.url?.absoluteString)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let comp = self.completion {
            self.completion = nil
            comp("")
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if let comp = self.completion {
            self.completion = nil
            comp("")
        }
    }
}
