import Foundation
import WebKit

/// Bắt request mạng cho browser ẩn của ext (`Engine.newBrowser()`): URL do `WebNetworkCaptureScript` báo về được gộp
/// với URL điều hướng, để `urls()` / `waitUrl` thấy mọi request của trang (XHR, fetch, media, iframe) như VBook.
/// Mọi hàm ở đây chạy trên main thread (handler WebKit và các block `_nativeBrowser*` đều nhảy về main).
extension WebViewLoader {
    /// Trần số request bắt được giữ lại mỗi lần launch; đủ rộng để link m3u8 đến muộn sau hàng trăm request quảng cáo
    /// vẫn được lưu. Quá trần thì không lưu thêm, nhưng vẫn so với `waitUrl` đang chờ.
    static let maxCapturedRequestUrls = 1000

    /// Kết quả `browser.urls()`: URL điều hướng trước, rồi request bắt được (không trùng), kể từ lần launch cuối.
    var allRequestedUrls: [String] {
        let navigation = Set(interceptedUrls)
        return interceptedUrls + capturedRequestUrls.filter { !navigation.contains($0) }
    }

    /// `mediaMode` chỉ bật cho ext video (đi cùng `mediaTypesRequiringUserActionForPlayback = []`): hook chủ động + ép tắt tiếng.
    func installNetworkCapture(mediaMode: Bool) {
        WebNetworkCaptureScript.install(
            into: webView.configuration.userContentController,
            mediaMode: mediaMode
        ) { [weak self] url, _ in
            self?.recordCapturedRequest(url)
        }
    }

    /// Ngữ nghĩa VBook: `urls()` chỉ tính từ lần `launch` / `launchAsync` gần nhất.
    func resetRequestedUrls() {
        interceptedUrls.removeAll()
        capturedRequestUrls.removeAll()
        capturedRequestUrlSet.removeAll()
    }

    func recordCapturedRequest(_ url: String) {
        // Domain quảng cáo/bị chặn: XHR tới đó không huỷ được từ native, nhưng cũng không đáng lưu.
        guard WebNetworkCaptureScript.isRecordable(url),
              !isEngineDomainBlocked(url),
              !isDynamicDomainBlocked(url) else { return }
        if capturedRequestUrls.count < Self.maxCapturedRequestUrls, capturedRequestUrlSet.insert(url).inserted {
            capturedRequestUrls.append(url)
        }
        completePendingWaitUrl(ifMatching: url)
    }

    /// Hoàn tất `waitUrl` đang chờ khi `url` khớp một mẫu (luật khớp: `WebNetworkCaptureScript.url(_:matchesWaitPattern:)`).
    func completePendingWaitUrl(ifMatching url: String) {
        guard let comp = waitUrlCompletion,
              targetUrlsToWait.contains(where: { WebNetworkCaptureScript.url(url, matchesWaitPattern: $0) }) else { return }
        waitUrlCompletion = nil
        targetUrlsToWait.removeAll()
        comp(true)
    }

    /// VBook: `waitUrl` trả về ngay nếu URL khớp đã được request kể từ lần launch cuối (thường request m3u8 bay ngay
    /// trong lúc `launch` còn chờ trang tải xong). Trả `true` khi đã hoàn tất.
    func completeWaitUrlIfAlreadyRequested() -> Bool {
        let targets = targetUrlsToWait
        guard let hit = allRequestedUrls.first(where: { url in
            targets.contains { WebNetworkCaptureScript.url(url, matchesWaitPattern: $0) }
        }) else { return false }
        completePendingWaitUrl(ifMatching: hit)
        return true
    }
}
