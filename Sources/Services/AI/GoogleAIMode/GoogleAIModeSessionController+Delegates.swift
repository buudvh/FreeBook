import Foundation
import WebKit

/// Delegate WebKit của `GoogleAIModeSessionController`, chỉ chuyển tiếp về các hàm sự kiện của controller.
/// Chỉ dùng biến thể `decidePolicyFor:preferences:` (luật 1.3.549 — WebKit chỉ gọi một trong hai biến thể).
extension GoogleAIModeSessionController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
        decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void
    ) {
        if navigationAction.targetFrame?.isMainFrame != false, shouldBlockNavigation(to: navigationAction.request.url) {
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame,
           let response = navigationResponse.response as? HTTPURLResponse,
           shouldBlockResponse(status: response.statusCode, url: response.url) {
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigationDidCommit(navigation)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDidCommit(navigation)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationDidFail(navigation, error: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationDidFail(navigation, error: error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessDidTerminate()
    }
}
