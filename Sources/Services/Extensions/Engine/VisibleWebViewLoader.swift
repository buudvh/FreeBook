import Foundation
import UIKit
import WebKit

public final class VisibleWebViewLoader: NSObject, UIAdaptivePresentationControllerDelegate {
    public let id: String
    public var titleString: String { viewController.titleString }
    public var interceptedUrls: [String] { viewController.interceptedUrls }
    let viewController: VisibleWebViewController
    internal var isCleaningUp = false
    var onClose: (() -> Void)?

    internal var waitForReadyCompletion: ((String) -> Void)?
    internal var isWaitingForReady = false
    internal var waitReadyTimerWorkItem: DispatchWorkItem?
    internal var waitReadyTimeoutWorkItem: DispatchWorkItem?

    init(id: String = UUID().uuidString, title: String) {
        self.id = id
        self.viewController = VisibleWebViewController(title: title)
        super.init()
        self.viewController.onDismiss = { [weak self] in
            self?.cleanUp()
        }
    }

    deinit {
        cleanUp()
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
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
            self.firePendingCompletions()
            self.cancelPendingWaitReady(reason: "Browser closed/cleaned up", cancelled: true)

            VisibleBrowserTabManager.shared.removeTab(id: id)

            let callback = onClose
            onClose = nil
            callback?()
        } else {
            DispatchQueue.main.async {
                self.cleanUp()
            }
        }
    }

    func cleanUpQuietly() {
        guard !isCleaningUp else { return }
        isCleaningUp = true

        self.viewController.webView.navigationDelegate = nil
        self.viewController.webView.stopLoading()
        self.firePendingCompletions()
        self.cancelPendingWaitReady(reason: "Browser closed/cleaned up", cancelled: true)

        let callback = onClose
        onClose = nil
        callback?()
    }

    /// Unblock JS bridge semaphores waiting on this loader by firing any pending
    /// callbacks. Without this, `_nativeBrowserLaunchVisible` / `_nativeBrowserWaitUrlVisible`
    /// would stall until their full timeout (up to ~16s) after the browser is closed.
    private func firePendingCompletions() {
        let navComp = viewController.navigationCompletion
        viewController.navigationCompletion = nil
        navComp?(nil)

        let waitComp = viewController.waitUrlCompletion
        viewController.waitUrlCompletion = nil
        waitComp?(false)
    }

    @MainActor
    func presentUIIfNeeded() {
        VisibleBrowserTabManager.shared.addTab(id: id, loader: self)
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

    func loadAsync(url: URL) {
        let request = URLRequest(url: url)
        DispatchQueue.main.async {
            self.presentUIIfNeeded()
            self.viewController.webView.load(request)
        }
    }

    func block(patterns: [String]) {
        self.viewController.dynamicBlockedPatterns.append(contentsOf: patterns)
    }

    func waitUrl(targetUrls: [String], timeout: TimeInterval, completion: @escaping (Bool) -> Void) {
        self.viewController.targetUrlsToWait = targetUrls
        self.viewController.waitUrlCompletion = completion

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self = self, let comp = self.viewController.waitUrlCompletion else { return }
            self.viewController.waitUrlCompletion = nil
            self.viewController.targetUrlsToWait = nil
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
