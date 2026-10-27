import Foundation
import WebKit

/// Browser ẩn dùng **một lần** cho fallback của `fetch` trong tiện ích (`JSExecutor+FetchBrowserFallback`): nạp lại cùng
/// URL bằng một `WebViewLoader` mới, chờ tới khi trang thật hiện ra rồi dọn dẹp và nhả loader.
///
/// Mọi hàm instance chạy trên **main**. Luồng JS chỉ `main.async` rồi chờ semaphore theo lát (không bao giờ chờ trên
/// main), nên không deadlock; driver tự giữ mình tới khi kết thúc và tự kết thúc muộn nhất ở `timeout`.
///
/// Không dùng `WebViewLoader.load(url:timeout:completion:)`: completion bắn ở `didFinish` **đầu tiên**, tức trang chờ
/// "Just a moment…" của Cloudflare. Thay vào đó mỗi `tickInterval` dò DOM bằng `evaluateJavaScript` và kết luận:
/// - **thành công**: DOM đã dựng (`readyState` ≠ loading), không còn dấu hiệu trang chặn, thân không rỗng, status
///   main-frame mới nhất < 400 (hoặc không biết), không có lỗi điều hướng. Trang chờ (gần như không chữ + script/meta
///   refresh) phải yên `interstitialQuietWindow` mới được nhận, vì nó thường tự chuyển trang;
/// - **thất bại sớm**: lỗi điều hướng (trừ -999) khi webView đã thôi tải; status ≥ 400 trên trang không phải trang
///   chặn/trang chờ và đã yên `errorQuietWindow` (403 của máy chủ, không còn cơ hội tự vượt);
/// - còn lại chờ tới `timeout` rồi thất bại với lý do của lần dò cuối (trang chặn / HTTP xxx / trang trống / hết giờ).
final class HiddenBrowserFetch {
    enum Outcome {
        case success(Page)
        case failure(reason: String, httpStatus: Int?)
        case cancelled
    }

    struct Page {
        let content: String
        /// MIME của phản hồi main-frame (ưu tiên) hoặc `document.contentType`.
        let contentType: String
        /// `document.characterSet` (vd "GBK", "UTF-8").
        let characterSet: String
        let finalURL: String
        let httpStatus: Int?
    }

    private enum BlockKind {
        case cloudflare
        case generic
    }

    /// Kết quả một lần dò DOM (`probeScript`); `nil` khi script lỗi.
    private struct Probe {
        let ready: Bool
        let empty: Bool
        let interstitial: Bool
        let markedBlock: BlockKind?
        let challengeScript: Bool

        init?(_ value: Any?) {
            guard let dict = value as? [String: Any] else { return nil }
            ready = dict["ready"] as? Bool ?? false
            empty = dict["empty"] as? Bool ?? true
            interstitial = dict["interstitial"] as? Bool ?? false
            challengeScript = dict["challengeScript"] as? Bool ?? false
            switch (dict["block"] as? String) ?? "" {
            case "cloudflare": markedBlock = .cloudflare
            case "generic": markedBlock = .generic
            default: markedBlock = nil
            }
        }

        /// Script `challenge-platform` một mình không đủ: Cloudflare chèn nó cả vào trang **thường** (dò bot) — chỉ tính
        /// là trang chặn khi status main-frame ≥ 400 (cùng quy tắc với `LegadoPageMarker`).
        func blockKind(failingStatus: Int?) -> BlockKind? {
            markedBlock ?? (challengeScript && failingStatus != nil ? .cloudflare : nil)
        }
    }

    /// Trần thời gian cho cả lượt browser.
    static let timeout: TimeInterval = 15
    /// Mỗi WKWebView là một tiến trình WebContent; tìm kiếm chạy nhiều nguồn song song nên giới hạn số browser cùng lúc.
    static let maxConcurrent = 3
    private static let slots = DispatchSemaphore(value: maxConcurrent)
    private static let tickInterval: TimeInterval = 0.5
    private static let slotWaitSlice: TimeInterval = 0.25
    private static let errorQuietWindow: TimeInterval = 2
    private static let interstitialQuietWindow: TimeInterval = 6

    private let loader: WebViewLoader
    private let deadline: Date
    private let isCancelled: () -> Bool
    private var completion: ((Outcome) -> Void)?
    /// Lúc webView thôi tải gần nhất; `nil` khi đang tải.
    private var quietSince: Date?
    private var probeInFlight = false
    private var lastProbe: Probe?
    /// Không ai khác giữ driver: tự giữ tới `finish`.
    private var keepAlive: HiddenBrowserFetch?

    // MARK: - Suất chạy (luồng JS)

    /// Gọi trên luồng JS (không bao giờ main): chờ một suất theo lát để còn kiểm huỷ. `true` ⇒ người gọi **phải** gọi
    /// `start` (driver trả suất khi kết thúc) hoặc `releaseSlot()`.
    static func acquireSlot(waitLimit: TimeInterval, isCancelled: () -> Bool) -> Bool {
        let giveUpAt = Date().addingTimeInterval(waitLimit)
        while slots.wait(timeout: .now() + slotWaitSlice) == .timedOut {
            if isCancelled() || Date() >= giveUpAt { return false }
        }
        return true
    }

    static func releaseSlot() {
        slots.signal()
    }

    // MARK: - Main thread

    /// Gọi trên main, khi người gọi đã giữ một suất. `completion` chạy đúng một lần, trên main.
    static func start(
        request: URLRequest,
        extensionLocalPath: String?,
        isCancelled: @escaping () -> Bool,
        completion: @escaping (Outcome) -> Void
    ) {
        let session = HiddenBrowserFetch(
            loader: WebViewLoader(extensionLocalPath: extensionLocalPath),
            isCancelled: isCancelled,
            completion: completion
        )
        session.begin(request)
    }

    private init(loader: WebViewLoader, isCancelled: @escaping () -> Bool, completion: @escaping (Outcome) -> Void) {
        self.loader = loader
        self.isCancelled = isCancelled
        self.completion = completion
        self.deadline = Date().addingTimeInterval(Self.timeout)
    }

    private func begin(_ request: URLRequest) {
        keepAlive = self
        // WebKit coi view ngoài window / khung 0×0 là "ẩn" (visibilityState, requestAnimationFrame, tiến trình WebContent có
        // thể bị tạm dừng) ⇒ JS của trang thử thách có thể không chạy. Gắn vào cửa sổ ẩn với khung cỡ màn hình; tiện ích
        // video đã tự gắn trong `init` của loader (gắn hai lần sẽ rò một cửa sổ).
        if loader.hiddenWindowHost == nil {
            MainActor.assumeIsolated { loader.webView.frame = WebViewLoader.mediaFrame }
            loader.attachToHiddenWindow()
        }
        loader.beginLaunch(request)
        scheduleTick()
    }

    private func scheduleTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.tickInterval) { [weak self] in
            self?.tick()
        }
    }

    private func tick() {
        guard completion != nil else { return }
        if isCancelled() {
            finish(.cancelled)
            return
        }
        let navigation = loader.mainFrameNavigation
        let loading = MainActor.assumeIsolated { loader.webView.isLoading }
        // Xét trước lỗi điều hướng: MIME không hiển thị được (octet-stream…) bị huỷ thành lỗi WebKit 102 khó hiểu hơn.
        if let mime = navigation.mimeType, Self.isBinaryMIME(mime) {
            finish(.failure(reason: "nội dung nhị phân (\(mime))", httpStatus: navigation.statusCode))
            return
        }
        if let error = navigation.error, !loading {
            finish(.failure(reason: WebViewLoader.errorSummary(error), httpStatus: navigation.statusCode))
            return
        }
        if Date() >= deadline {
            finish(.failure(reason: deadlineReason(), httpStatus: navigation.statusCode))
            return
        }
        if loading {
            quietSince = nil
        } else if quietSince == nil {
            quietSince = Date()
        }
        if !probeInFlight {
            runProbe()
        }
        scheduleTick()
    }

    private func runProbe() {
        probeInFlight = true
        MainActor.assumeIsolated {
            loader.webView.evaluateJavaScript(HiddenBrowserFetchScripts.probe) { [weak self] value, _ in
                guard let self else { return }
                self.probeInFlight = false
                guard self.completion != nil, let probe = Probe(value) else { return }
                self.lastProbe = probe
                self.evaluate(probe)
            }
        }
    }

    private func evaluate(_ probe: Probe) {
        let navigation = loader.mainFrameNavigation
        let loading = MainActor.assumeIsolated { loader.webView.isLoading }
        // Điều hướng mới đã bắt đầu nhưng chưa có phản hồi: DOM đang hiện vẫn là trang cũ.
        if loading && navigation.statusCode == nil { return }
        let failingStatus = navigation.statusCode.flatMap { $0 >= 400 ? $0 : nil }
        let blocked = probe.blockKind(failingStatus: failingStatus) != nil
        let quiet: TimeInterval = loading ? 0 : (quietSince.map { Date().timeIntervalSince($0) } ?? 0)
        if let failingStatus {
            // Trang lỗi của máy chủ (kể cả thân rỗng) — không phải trang chặn/trang chờ, đã yên: không còn cơ hội tự vượt.
            if probe.ready && !blocked && !probe.interstitial && quiet >= Self.errorQuietWindow {
                finish(.failure(reason: "HTTP \(failingStatus)", httpStatus: failingStatus))
            }
            return
        }
        guard probe.ready, !probe.empty, !blocked else { return }
        if probe.interstitial && quiet < Self.interstitialQuietWindow { return }
        readContent()
    }

    private func readContent() {
        probeInFlight = true
        MainActor.assumeIsolated {
            loader.webView.evaluateJavaScript(HiddenBrowserFetchScripts.content) { [weak self] value, _ in
                guard let self else { return }
                self.probeInFlight = false
                guard self.completion != nil,
                      let dict = value as? [String: Any],
                      let content = dict["content"] as? String,
                      !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let navigation = self.loader.mainFrameNavigation
                // Status đổi trong lúc đọc (điều hướng mới trả lỗi) ⇒ dò lại ở nhịp sau.
                if let status = navigation.statusCode, status >= 400 { return }
                let documentType = (dict["contentType"] as? String) ?? ""
                let pageURL = (dict["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? self.loader.webView.url?.absoluteString ?? ""
                self.finish(.success(Page(
                    content: content,
                    contentType: navigation.mimeType ?? documentType,
                    characterSet: (dict["characterSet"] as? String) ?? "",
                    finalURL: pageURL,
                    httpStatus: navigation.statusCode
                )))
            }
        }
    }

    /// Trang chính là ảnh/âm thanh/video/HLS/PDF/nhị phân: browser không cho ra văn bản được ⇒ thất bại ngay (không chờ
    /// 15 s, và không để m3u8/video tự phát trong cửa sổ ẩn).
    private static func isBinaryMIME(_ mime: String) -> Bool {
        mime.hasPrefix("image/") || mime.hasPrefix("audio/") || mime.hasPrefix("video/") || mime.contains("mpegurl")
            || mime == "application/octet-stream" || mime == "application/pdf"
    }

    /// Lý do thất bại khi hết `timeout`, theo lần dò cuối và status main-frame mới nhất.
    private func deadlineReason() -> String {
        let seconds = Int(Self.timeout)
        let failingStatus = loader.mainFrameNavigation.statusCode.flatMap { $0 >= 400 ? $0 : nil }
        let httpSuffix = failingStatus.map { " (HTTP \($0))" } ?? ""
        guard let probe = lastProbe else { return "hết giờ" }
        switch probe.blockKind(failingStatus: failingStatus) {
        case .cloudflare?: return "trang chặn Cloudflare sau \(seconds)s" + httpSuffix
        case .generic?: return "trang chặn sau \(seconds)s" + httpSuffix
        case nil: break
        }
        if let failingStatus { return "HTTP \(failingStatus)" }
        if probe.ready && probe.empty { return "trang trống" }
        if probe.ready && probe.interstitial { return "trang chờ không tự chuyển sau \(seconds)s" }
        return "hết giờ"
    }

    /// Kết thúc đúng một lần: dọn loader trên main (gỡ cửa sổ ẩn, dừng tải), trả suất, nhả chính mình.
    private func finish(_ outcome: Outcome) {
        guard let completion else { return }
        self.completion = nil
        MainActor.assumeIsolated { loader.cleanUp() }
        Self.releaseSlot()
        keepAlive = nil
        completion(outcome)
    }
}
