import Foundation
import UIKit
import WebKit

/// Dò link media thật (m3u8/mp4…) của trang xem/embed cho track `auto` và `webview`: nạp trang vào WKWebView ẩn có
/// script bắt request (`WebNetworkCaptureScript`), cho autoplay tắt tiếng rồi thử `play()`; ứng viên khớp đuôi
/// `.m3u8|.mp4|.m4v|.webm|.mov` trên **path** (bỏ `.ts`, `.mpd`) hoặc response có MIME video/HLS.
///
/// - m3u8 thấy là chốt ngay; mp4… thì chờ thêm `progressiveGrace` vì link đầu thường là quảng cáo pre-roll và
///   m3u8 vẫn được ưu tiên. Quá `timeout` thì trả ứng viên tốt nhất hoặc `nil`.
/// - WebView được gắn vào cửa sổ ẩn (`GeminiWebHiddenWindowHost`): WKWebView ngoài window bị WebKit tạm dừng tiến
///   trình WebContent và chặn phát media. Giải phóng ngay khi có kết quả, hết giờ hoặc bị huỷ.
/// - Mỗi sniffer phục vụ một lượt `sniff` tại một thời điểm; gọi lại sẽ huỷ lượt cũ.
@MainActor
final class VideoMediaSniffer: NSObject, WKNavigationDelegate {
    struct Result: Sendable {
        let url: URL
        /// `Referer` = URL frame phát request (trang chính nếu không rõ), kèm `Origin` và UA iPhone Safari.
        /// Khoá `User-Agent` giữ trong dict; khi dựng `AVURLAsset`, `VideoPlayerController.assetOptions` tách nó sang
        /// `AVURLAssetHTTPUserAgentKey` (UA trong header fields có thể bị AVFoundation bỏ qua).
        let headers: [String: String]
    }

    enum Page {
        case url(URL)
        case html(String, baseURL: URL?)
    }

    private enum MediaKind {
        case hls
        case progressive
    }

    private struct Candidate {
        let url: URL
        let frameURL: URL?
    }

    static let timeout: TimeInterval = 20
    private static let progressiveGrace: TimeInterval = 2
    /// Cùng UA với `fetch` của ext (`JSExecutor`) và `WebViewLoader`.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    private static let progressiveExtensions: Set<String> = ["mp4", "m4v", "webm", "mov"]
    private static let playProbeScript = """
    (function () {
        var video = document.querySelector('video');
        if (!video) { return; }
        video.muted = true;
        var pending = video.play();
        if (pending && typeof pending.catch === 'function') { pending.catch(function () {}); }
    })();
    """

    private let windowHost = GeminiWebHiddenWindowHost()
    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Result?, Error>?
    private var pageURL: URL?
    private var hlsCandidate: Candidate?
    private var progressiveCandidate: Candidate?
    private var seenUrls = Set<String>()
    private var timeoutTask: Task<Void, Never>?
    private var graceTask: Task<Void, Never>?

    /// `nil` = không thấy link media; huỷ (`cancel()` hoặc Task bị huỷ) thì ném `CancellationError`.
    func sniff(_ page: Page) async throws -> Result? {
        cancel()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Result?, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                self.start(page)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func cancel() {
        guard continuation != nil else {
            tearDown()
            return
        }
        complete(.failure(CancellationError()), reason: "huỷ")
    }

    // MARK: - Vòng đời

    private func start(_ page: Page) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        WebNetworkCaptureScript.install(
            into: config.userContentController,
            mediaMode: true,
            playMediaOnLoad: true
        ) { [weak self] url, frameURL in
            MainActor.assumeIsolated {
                self?.consider(url, frameURL: frameURL, kind: nil)
            }
        }

        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.customUserAgent = Self.userAgent
        view.navigationDelegate = self
        view.isUserInteractionEnabled = false
        windowHost.attach(view)
        webView = view

        switch page {
        case .url(let url):
            pageURL = url
            view.load(URLRequest(url: url))
        case .html(let html, let baseURL):
            pageURL = baseURL
            view.loadHTMLString(html, baseURL: baseURL)
        }

        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.completeWithBestCandidate(reason: "hết \(Int(Self.timeout)) giây")
        }
    }

    private func completeWithBestCandidate(reason: String) {
        guard let pick = hlsCandidate ?? progressiveCandidate else {
            complete(.success(nil), reason: reason)
            return
        }
        complete(.success(makeResult(pick)), reason: reason)
    }

    private func complete(_ outcome: Swift.Result<Result?, Error>, reason: String) {
        let pending = continuation
        continuation = nil
        tearDown()
        guard let pending else { return }
        switch outcome {
        case .success(let result?):
            AppLogger.shared.log("🎬 [VideoMediaSniffer] Bắt được \(Self.redacted(result.url)) (\(reason))")
        case .success(nil):
            AppLogger.shared.log("⚠️ [VideoMediaSniffer] Không thấy link media (\(reason))")
        case .failure:
            break
        }
        pending.resume(with: outcome)
    }

    private func tearDown() {
        timeoutTask?.cancel()
        timeoutTask = nil
        graceTask?.cancel()
        graceTask = nil
        if let view = webView {
            view.configuration.userContentController.removeScriptMessageHandler(forName: WebNetworkCaptureScript.handlerName)
            view.configuration.userContentController.removeAllUserScripts()
            view.navigationDelegate = nil
            view.stopLoading()
            windowHost.detach(view)
        }
        webView = nil
        pageURL = nil
        hlsCandidate = nil
        progressiveCandidate = nil
        seenUrls.removeAll()
    }

    // MARK: - Ứng viên

    private func consider(_ urlString: String, frameURL: URL?, kind explicitKind: MediaKind?) {
        // Phân loại trước rồi mới đánh dấu đã thấy: cùng một URL có thể tới lần đầu không rõ loại (điều hướng iframe)
        // rồi mới có MIME video ở response.
        guard continuation != nil,
              let url = URL(string: urlString),
              let kind = explicitKind ?? Self.mediaKind(ofPath: url),
              !isEngineDomainBlocked(urlString),
              seenUrls.insert(urlString).inserted else { return }
        let candidate = Candidate(url: url, frameURL: frameURL)
        switch kind {
        case .hls:
            if hlsCandidate == nil { hlsCandidate = candidate }
            completeWithBestCandidate(reason: "m3u8")
        case .progressive:
            guard progressiveCandidate == nil else { return }
            progressiveCandidate = candidate
            graceTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.progressiveGrace * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.completeWithBestCandidate(reason: "mp4/webm")
            }
        }
    }

    private func makeResult(_ candidate: Candidate) -> Result {
        var headers = ["User-Agent": Self.userAgent]
        let referer = [candidate.frameURL, pageURL].compactMap { $0 }.first { Self.isWebURL($0) && $0 != candidate.url }
        if let referer {
            headers["Referer"] = referer.absoluteString
            if let scheme = referer.scheme, let host = referer.host {
                headers["Origin"] = "\(scheme)://\(host)" + (referer.port.map { ":\($0)" } ?? "")
            }
        }
        return Result(url: candidate.url, headers: headers)
    }

    /// Phân loại theo đuôi của **path** (không xét query, tránh nhận nhầm trang player `?file=a.mp4`).
    static func isDirectMediaURL(_ url: URL) -> Bool {
        mediaKind(ofPath: url) != nil
    }

    private static func mediaKind(ofPath url: URL) -> MediaKind? {
        guard isWebURL(url) else { return nil }
        let ext = url.pathExtension.lowercased()
        if ext == "m3u8" { return .hls }
        return progressiveExtensions.contains(ext) ? .progressive : nil
    }

    private static func mediaKind(ofMimeType mimeType: String?) -> MediaKind? {
        guard let mime = mimeType?.lowercased() else { return nil }
        if mime.contains("mpegurl") { return .hls }
        if mime.hasPrefix("video/"), !mime.contains("mp2t"), !mime.contains("dash") { return .progressive }
        return nil
    }

    private static func isWebURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    /// Chỉ host + tên file, không log query (thường chứa token).
    static func redacted(_ url: URL) -> String {
        "\(url.host ?? "?")/…/\(url.lastPathComponent)"
    }

    // MARK: - WKNavigationDelegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        if isEngineDomainBlocked(url.absoluteString) {
            decisionHandler(.cancel)
            return
        }
        consider(url.absoluteString, frameURL: pageURL, kind: nil)
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        // Frame nạp thẳng file media (iframe src = m3u8/mp4): đã có URL thì không cần WebKit phát.
        if let url = navigationResponse.response.url,
           let kind = Self.mediaKind(ofMimeType: navigationResponse.response.mimeType) {
            consider(url.absoluteString, frameURL: pageURL, kind: kind)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript(Self.playProbeScript, completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleLoadFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        completeWithBestCandidate(reason: "tiến trình WebContent dừng")
    }

    /// Lỗi tải thật thì chốt sớm thay vì chờ đủ 20 giây; bỏ qua huỷ điều hướng (-999), điều hướng bị policy chặn
    /// (WebKit 102) và "plug-in handled load" (WebKit 204, khung tự phát media).
    private func handleLoadFailure(_ error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 || nsError.code == 204 { return }
        AppLogger.shared.log("❌ [VideoMediaSniffer] Trang xem lỗi tải: \(nsError.domain) \(nsError.code)")
        completeWithBestCandidate(reason: "trang lỗi tải")
    }
}
