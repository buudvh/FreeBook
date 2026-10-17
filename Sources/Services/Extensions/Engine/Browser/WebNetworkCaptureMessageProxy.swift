import Foundation
import WebKit

/// Handler `fbNetCapture` dùng chung cho `WebViewLoader`, `VisibleWebViewController` và `VideoMediaSniffer`.
///
/// `WKUserContentController` giữ handler bằng tham chiếu **mạnh**, nên proxy không giữ chủ mà chỉ giữ closure;
/// closure do chủ truyền vào phải tự `[weak self]`. Nhờ vậy không có vòng giữ
/// webView → configuration → userContentController → handler → chủ.
final class WebNetworkCaptureMessageProxy: NSObject, WKScriptMessageHandler {
    private let onRequest: (String, URL?) -> Void

    /// `onRequest(url, frameURL)`: URL tuyệt đối http(s) mà trang đã request, kèm URL của frame phát request
    /// (iframe player thường khác host với trang chính). WebKit gọi handler trên main thread.
    init(onRequest: @escaping (String, URL?) -> Void) {
        self.onRequest = onRequest
        super.init()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == WebNetworkCaptureScript.handlerName,
              let url = message.body as? String,
              WebNetworkCaptureScript.isRecordable(url) else { return }
        onRequest(url, message.frameInfo.request.url)
    }
}
