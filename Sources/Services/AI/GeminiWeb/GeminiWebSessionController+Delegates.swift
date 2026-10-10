import Foundation
import WebKit

/// Các delegate WebKit của `GeminiWebSessionController`, chỉ chuyển tiếp về các hàm sự kiện của controller.
/// Tách file để file chính dưới 400 dòng; không có logic ở đây.
extension GeminiWebSessionController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handleScriptMessage(message.body)
    }
}

extension GeminiWebSessionController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        navigationDidStart()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        navigationDidCommitOrFinish()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationDidCommitOrFinish()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationDidFail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationDidFail(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        contentProcessDidTerminate()
    }
}
