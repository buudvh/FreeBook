import Foundation
import WebKit

/// Ghi lại mã HTTP, MIME và lỗi của điều hướng main-frame **mới nhất**, để người dùng `WebViewLoader` (fallback `fetch` →
/// `HiddenBrowserFetch`) phân biệt trang thật với trang lỗi. Trước đây loader bỏ `Error` của `didFail*` và không biết
/// status: trang 403 của máy chủ trông y như trang thường.
///
/// Trang thử thách Cloudflare trả 403/503 rồi tự điều hướng sang trang thật 200 ⇒ trạng thái reset ở
/// `didStartProvisionalNavigation` và luôn là của điều hướng gần nhất. Mọi hàm chạy trên main (delegate WebKit).
extension WebViewLoader {
    struct MainFrameNavigationState {
        /// `nil` khi điều hướng hiện tại chưa có phản hồi (hoặc không phải HTTP).
        var statusCode: Int?
        var mimeType: String?
        /// Lỗi điều hướng gần nhất, đã bỏ -999 (điều hướng bị điều hướng mới thay thế).
        var error: NSError?
    }

    /// Mô phỏng đúng mặc định của WebKit khi delegate không cài hàm này (URL file: phải tồn tại và không là thư mục;
    /// còn lại: hiển thị được MIME thì cho, không thì huỷ) — `Engine.newBrowser`, Legado, video không đổi hành vi, chỉ
    /// thêm việc ghi status/MIME. Selector ghi tường minh để chắc chắn WebKit gọi tới hàm nằm trong extension này.
    @objc(webView:decidePolicyForNavigationResponse:decisionHandler:)
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        if navigationResponse.isForMainFrame {
            mainFrameNavigation.statusCode = (navigationResponse.response as? HTTPURLResponse)?.statusCode
            mainFrameNavigation.mimeType = navigationResponse.response.mimeType?.lowercased()
        }
        let canShow = navigationResponse.canShowMIMEType
        if let url = navigationResponse.response.url, url.isFileURL {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            decisionHandler(exists && !isDirectory.boolValue && canShow ? .allow : .cancel)
            return
        }
        decisionHandler(canShow ? .allow : .cancel)
    }

    /// Gọi đầu `didFail` / `didFailProvisionalNavigation` (chỉ báo cho main-frame). -999 không phải lỗi: đó là điều hướng
    /// bị thay bởi điều hướng mới (trang thử thách tự chuyển trang, script đổi `location`).
    func recordNavigationFailure(_ error: Error) {
        let nsError = error as NSError
        guard !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) else { return }
        mainFrameNavigation.error = nsError
    }

    /// `"<domain> <code>: <mô tả>"` — dùng cho log và `statusText` gộp lỗi.
    static func errorSummary(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(nsError.domain) \(nsError.code): \(nsError.localizedDescription)"
    }
}
