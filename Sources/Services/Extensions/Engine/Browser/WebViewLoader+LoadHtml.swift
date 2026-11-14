import Foundation
import WebKit

/// `browser.loadHtml` của hợp đồng tiện ích (1.3.947): nạp **HTML có sẵn** với URL gốc rồi chờ trang chạy xong — như
/// `load(url:)` (xoá danh sách URL đã bắt, trả DOM ở `didFinish`, hết giờ thì trả DOM đang có), chỉ khác nguồn trang.
/// Tiện ích TTS ChillAudio dựng trang gọi API đọc bằng cách này (log 22: `browser.loadHtml is not a function`).
extension WebViewLoader {
    func loadHtml(_ html: String, baseURL: URL?, timeout: TimeInterval, completion: @escaping (String?) -> Void) {
        self.completion = completion
        resetRequestedUrls()
        webView.loadHTMLString(html, baseURL: baseURL)

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, let comp = self.completion else { return }
            self.completion = nil
            self.webView.evaluateJavaScript("document.documentElement.outerHTML") { result, _ in
                comp(result as? String ?? "")
            }
        }
    }
}
