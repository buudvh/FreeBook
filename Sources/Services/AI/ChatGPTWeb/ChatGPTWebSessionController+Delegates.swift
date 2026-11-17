import Foundation
import WebKit

/// Delegate WebKit của `ChatGPTWebSessionController`, chỉ chuyển tiếp về các hàm sự kiện của controller. Không chặn điều
/// hướng hay phản hồi nào: trang kiểm tra của Cloudflare (HTTP 403) phải được nạp thì mới tự qua.
extension ChatGPTWebSessionController: WKNavigationDelegate {
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
