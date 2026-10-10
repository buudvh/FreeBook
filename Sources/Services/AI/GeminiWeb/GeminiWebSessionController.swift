import Foundation
import WebKit

/// Chủ sở hữu **duy nhất** của WKWebView ẩn đã đăng nhập gemini.google.com, và là nơi duy nhất chạy
/// giao thức web của Gemini — bằng `fetch()` **trong chính trang đó**.
///
/// Vì sao không copy cookie sang `URLSession`: `__Secure-1PSIDTS` là cookie HttpOnly xoay liên tục và
/// Google gắn phiên với dấu vân tay trình duyệt — để WebKit tự lo cookie/Origin/TLS (xem `rules.md`).
/// WebView **không gắn vào window** (giống `WebViewLoader`) nhưng dùng `WKWebsiteDataStore.default()` —
/// cùng kho cookie với `GeminiWebLoginView`. Mọi hàm chạy trên MainActor; `GeminiWebClient` (actor) gọi
/// vào đây rồi bóc frame ở ngoài. WebView tự giải phóng sau 10 phút không dùng.
///
/// Hai bài học 1.3.506: (1) chờ `didCommit` chứ **không** chờ `didFinish` — `WIZ_global_data` nằm trong
/// script inline đầu HTML, còn sự kiện `load` của app Gemini nặng có thể quá 30 s trên mạng di động;
/// (2) timeout của `fetch` tính **theo chunk** (idle), và mọi bước đều có log để phân định treo ở đâu.
/// JavaScript tiêm vào trang: `+Scripts.swift`; delegate WebKit: `+Delegates.swift`.
@MainActor
final class GeminiWebSessionController: NSObject {
    static let shared = GeminiWebSessionController()

    /// UA Safari iOS — cùng chuỗi với trình duyệt bypass; Google từ chối đăng nhập khi nhận ra WebView nhúng.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"
    static let messageHandlerName = "geminiWebStream"
    /// Không nhận chunk nào trong khoảng này ⇒ `.timeout`.
    static let defaultIdleTimeout: TimeInterval = 45

    private static let commitTimeout: TimeInterval = 30
    /// 90 × 0,5 s = 45 s chờ `WIZ_global_data` sau khi HTML commit.
    private static let tokenProbeAttempts = 90
    /// Trần tuyệt đối của một `fetch`, kể cả khi vẫn còn chunk về.
    private static let absoluteTimeout: TimeInterval = 240
    private static let watchdogInterval: UInt64 = 5_000_000_000
    private static let idleReleaseSeconds: TimeInterval = 10 * 60

    /// Một `fetch` đang bay trong trang.
    private struct StreamState {
        let continuation: AsyncThrowingStream<String, Error>.Continuation
        let kind: String
        let startedAt: Date
        let idleTimeout: TimeInterval
        var lastActivity: Date
        var chunks = 0
        var watchdog: Task<Void, Never>?
    }

    private var webView: WKWebView?
    private var initSession: GeminiWebInitSession?
    private var navigationWaiters: [CheckedContinuation<Void, Error>] = []
    /// `true` giữa lúc `load()` gọi và lúc commit — để phân biệt điều hướng của ta với điều hướng do trang tự làm.
    private var expectingNavigation = false
    private var streams: [String: StreamState] = [:]
    private var requestCounter = Int.random(in: 10_000...99_999)
    private var idleReleaseTask: Task<Void, Never>?
    private var prepareTask: Task<GeminiWebInitSession, Error>?

    private override init() {
        super.init()
    }

    // MARK: - Phiên

    /// `_reqid` tăng 100 000 mỗi request, khởi đầu ngẫu nhiên — theo thư viện tham chiếu.
    func nextRequestId() -> Int {
        requestCounter += 100_000
        return requestCounter
    }

    /// Nạp (hoặc dùng lại) phiên: trang `/app` đã commit và `WIZ_global_data` có token. Các lời gọi đồng
    /// thời gộp vào một `Task` để hai lượt chat cùng lúc không nạp trang hai lần.
    func prepare(force: Bool = false) async throws -> GeminiWebInitSession {
        if !force, let session = initSession, !session.isStale {
            touch()
            return session
        }
        if let running = prepareTask {
            return try await running.value
        }
        let task = Task<GeminiWebInitSession, Error> { [self] in
            defer { self.prepareTask = nil }
            let startedAt = Date()
            let webView = self.ensureWebView()
            try await self.load(GeminiWebRequestBuilder.appURL, in: webView, forceReload: force)
            let session = try await self.probeInitSession(in: webView)
            self.initSession = session
            self.touch()
            AppLogger.shared.log("🤖 [GeminiWeb] Phiên sẵn sàng sau \(Self.ms(since: startedAt)) ms (hl=\(session.language), bl=\(session.buildLabel ?? "-"), host=\(webView.url?.host ?? "-"))")
            return session
        }
        prepareTask = task
        return try await task.value
    }

    /// Sau khi đăng nhập/đăng xuất: lượt gọi kế tiếp phải nạp lại trang để lấy token mới.
    func invalidateSession() {
        initSession = nil
    }

    func isSignedIn() async -> Bool {
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        return cookies.contains { $0.name == "__Secure-1PSID" && $0.domain.hasSuffix("google.com") }
    }

    /// Xoá mọi cookie `*.google.com` của kho mặc định — **cũng** đăng xuất Google trong trình duyệt bypass của app.
    func signOut() async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let cookies = await store.allCookies()
        for cookie in cookies where cookie.domain.hasSuffix("google.com") {
            await store.deleteCookie(cookie)
        }
        initSession = nil
        releaseWebView()
        AppLogger.shared.log("🤖 [GeminiWeb] Đã đăng xuất Google (xoá cookie *.google.com)")
    }

    // MARK: - Fetch trong trang

    /// Chạy `fetch()` trong trang, trả về **chunk text thô** của body theo thứ tự nhận được. Yêu cầu
    /// `prepare()` đã thành công trước đó; huỷ stream là huỷ `fetch` (AbortController).
    func fetchStream(
        _ request: GeminiWebRequestBuilder.Request,
        idleTimeout: TimeInterval = GeminiWebSessionController.defaultIdleTimeout
    ) -> AsyncThrowingStream<String, Error> {
        let id = UUID().uuidString
        let kind = request.url.contains("batchexecute") ? "batchexecute" : "StreamGenerate"
        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView, self.initSession != nil else {
                    continuation.finish(throwing: GeminiWebError.sessionUnavailable)
                    return
                }
                let now = Date()
                var state = StreamState(continuation: continuation, kind: kind, startedAt: now, idleTimeout: idleTimeout, lastActivity: now)
                state.watchdog = self.makeWatchdog(id: id)
                self.streams[id] = state
                self.touch()
                continuation.onTermination = { [weak self] _ in
                    Task { @MainActor in self?.abortScript(id: id) }
                }

                do {
                    let script = try Self.fetchScript(id: id, request: request)
                    webView.evaluateJavaScript(script) { _, error in
                        guard let error else { return }
                        Task { @MainActor [weak self] in
                            self?.finishStream(id: id, error: GeminiWebError.script(error.localizedDescription))
                        }
                    }
                    AppLogger.shared.log("🤖 [GeminiWeb] \(kind) bắt đầu (\(id.prefix(8)), idle \(Int(idleTimeout)) s)")
                } catch {
                    self.finishStream(id: id, error: error)
                }
            }
        }
    }

    /// Một Task cho mỗi stream, 5 s kiểm tra một lần: quá idle hoặc quá trần tuyệt đối ⇒ `.timeout`.
    private func makeWatchdog(id: String) -> Task<Void, Never> {
        Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.watchdogInterval)
                guard !Task.isCancelled, let self, let state = self.streams[id] else { return }
                let idle = Date().timeIntervalSince(state.lastActivity)
                let total = Date().timeIntervalSince(state.startedAt)
                if idle > state.idleTimeout || total > Self.absoluteTimeout {
                    AppLogger.shared.log("🤖 [GeminiWeb] \(state.kind) timeout (idle \(Int(idle)) s, tổng \(Int(total)) s, chunk=\(state.chunks))")
                    self.finishStream(id: id, error: GeminiWebError.timeout)
                    return
                }
            }
        }
    }

    /// Message từ JS trong trang (gọi từ `+Delegates.swift`).
    func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let id = dict["id"] as? String else { return }
        let type = dict["type"] as? String ?? ""
        let payload = dict["payload"] as? String ?? ""
        switch type {
        case "chunk":
            guard !payload.isEmpty, var state = streams[id] else { return }
            state.lastActivity = Date()
            state.chunks += 1
            if state.chunks == 1 {
                AppLogger.shared.log("🤖 [GeminiWeb] \(state.kind) nhận chunk đầu sau \(Self.ms(since: state.startedAt)) ms")
            }
            streams[id] = state
            state.continuation.yield(payload)
        case "done":
            finishStream(id: id, error: nil)
        case "error":
            finishStream(id: id, error: Self.scriptError(from: payload))
        default:
            break
        }
    }

    private func finishStream(id: String, error: Error?) {
        guard let state = streams.removeValue(forKey: id) else { return }
        state.watchdog?.cancel()
        let elapsed = Self.ms(since: state.startedAt)
        if let error {
            AppLogger.shared.log("🤖 [GeminiWeb] \(state.kind) lỗi sau \(elapsed) ms, chunk=\(state.chunks): \(error.localizedDescription)")
            state.continuation.finish(throwing: error)
        } else {
            AppLogger.shared.log("🤖 [GeminiWeb] \(state.kind) xong sau \(elapsed) ms, chunk=\(state.chunks)")
            state.continuation.finish()
        }
    }

    /// Consumer dừng sớm (đổi chương, huỷ chat): huỷ `fetch` tương ứng trong trang. Stream đã kết thúc
    /// bình thường thì không còn trong `streams` nên không làm gì.
    private func abortScript(id: String) {
        guard let state = streams.removeValue(forKey: id) else { return }
        state.watchdog?.cancel()
        guard let webView, let idLiteral = try? Self.jsLiteral(id) else { return }
        let script = "(function(){try{var c=window.__fbGeminiAbort&&window.__fbGeminiAbort[\(idLiteral)];if(c){c.abort();}}catch(e){}return true;})();"
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    private func failAllStreams(_ error: GeminiWebError) {
        for id in Array(streams.keys) {
            finishStream(id: id, error: error)
        }
    }

    // MARK: - WebView ẩn

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.userContentController.add(self, name: Self.messageHandlerName)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.customUserAgent = Self.userAgent
        view.navigationDelegate = self
        webView = view
        return view
    }

    func releaseWebView() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        guard let view = webView else { return }
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.messageHandlerName)
        view.navigationDelegate = nil
        view.stopLoading()
        webView = nil
        initSession = nil
        failAllStreams(.sessionUnavailable)
        failNavigationWaiters(GeminiWebError.sessionUnavailable)
    }

    /// Mỗi lần dùng dời mốc giải phóng; không có stream nào bay và không nạp trang dở thì mới giải phóng.
    private func touch() {
        idleReleaseTask?.cancel()
        idleReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleReleaseSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.streams.isEmpty, self.prepareTask == nil else { return }
            AppLogger.shared.log("🤖 [GeminiWeb] Giải phóng WKWebView ẩn sau \(Int(Self.idleReleaseSeconds)) s không dùng")
            self.releaseWebView()
        }
    }

    /// Nạp trang và chờ tới **commit** (HTML bắt đầu về). Stream đang bay (nếu có) chết theo document cũ
    /// nên fail ngay bằng `.documentChanged` để lượt retry không phải chờ idle timeout.
    private func load(_ url: URL, in webView: WKWebView, forceReload: Bool) async throws {
        if !streams.isEmpty {
            AppLogger.shared.log("🤖 [GeminiWeb] Nạp lại trang khi còn \(streams.count) fetch đang bay — huỷ chúng")
            failAllStreams(.documentChanged)
        }
        let startedAt = Date()
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.commitTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            AppLogger.shared.log("🤖 [GeminiWeb] Trang /app không commit sau \(Int(Self.commitTimeout)) s")
            self?.failNavigationWaiters(GeminiWebError.timeout)
        }
        defer { timeoutTask.cancel() }
        expectingNavigation = true
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationWaiters.append(continuation)
            let policy: URLRequest.CachePolicy = forceReload ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
            webView.load(URLRequest(url: url, cachePolicy: policy, timeoutInterval: Self.commitTimeout))
        }
        AppLogger.shared.log("🤖 [GeminiWeb] Trang commit sau \(Self.ms(since: startedAt)) ms, host=\(webView.url?.host ?? "-")")
    }

    private func resumeNavigationWaiters() {
        let waiters = navigationWaiters
        navigationWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    private func failNavigationWaiters(_ error: Error) {
        let waiters = navigationWaiters
        navigationWaiters.removeAll()
        waiters.forEach { $0.resume(throwing: error) }
    }

    /// Đọc `WIZ_global_data` ngay sau commit; script inline chạy sớm nhưng trang vẫn đang tải nên thử lại
    /// 0,5 s/lần. `evaluateJavaScript` có thể lỗi thoáng qua lúc trang đổi document — bỏ qua, thử lại.
    private func probeInitSession(in webView: WKWebView) async throws -> GeminiWebInitSession {
        let startedAt = Date()
        var sawWizWithoutToken = 0
        var loggedEvaluateFailure = false
        for attempt in 0..<Self.tokenProbeAttempts {
            if let host = webView.url?.host?.lowercased(), host.contains("accounts.google.com") {
                AppLogger.shared.log("🤖 [GeminiWeb] Trang chuyển sang \(host) — chưa đăng nhập")
                throw GeminiWebError.notSignedIn
            }
            do {
                if let dict = try await evaluate(Self.probeScript, in: webView) as? [String: Any] {
                    if ((dict["href"] as? String) ?? "").contains("accounts.google.com") { throw GeminiWebError.notSignedIn }
                    let token = (dict["token"] as? String) ?? ""
                    if !token.isEmpty {
                        return GeminiWebInitSession(
                            accessToken: token,
                            buildLabel: Self.nonEmpty(dict["bl"]),
                            sessionId: Self.nonEmpty(dict["sid"]),
                            language: Self.nonEmpty(dict["hl"]) ?? "en"
                        )
                    }
                    if (dict["hasWiz"] as? Bool) == true {
                        sawWizWithoutToken += 1
                        // Trang đã dựng xong mà vẫn không có SNlM0e: phiên khách, chưa đăng nhập.
                        if sawWizWithoutToken >= 4 {
                            AppLogger.shared.log("🤖 [GeminiWeb] WIZ_global_data có nhưng không có SNlM0e — phiên khách")
                            throw GeminiWebError.notSignedIn
                        }
                    }
                }
            } catch let error as GeminiWebError where error == .notSignedIn {
                throw error
            } catch {
                if !loggedEvaluateFailure {
                    loggedEvaluateFailure = true
                    AppLogger.shared.log("🤖 [GeminiWeb] Probe WIZ_global_data lỗi thoáng qua: \(error.localizedDescription)")
                }
            }
            if attempt == 20 {
                AppLogger.shared.log("🤖 [GeminiWeb] Vẫn chờ WIZ_global_data sau 10 s (host=\(webView.url?.host ?? "-"))")
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        AppLogger.shared.log("🤖 [GeminiWeb] Không thấy WIZ_global_data.SNlM0e sau \(Self.ms(since: startedAt)) ms, host=\(webView.url?.host ?? "-")")
        throw GeminiWebError.protocolChanged("trang /app không có WIZ_global_data.SNlM0e sau 45 s")
    }

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: GeminiWebError.script(error.localizedDescription))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    // MARK: - Sự kiện điều hướng (gọi từ `+Delegates.swift`)

    /// Điều hướng **không** do `load()` của ta (trang tự `location.replace`…): fetch đang bay chết theo
    /// document cũ ⇒ fail ngay bằng `.documentChanged` (retryable) thay vì chờ idle timeout.
    func navigationDidStart() {
        guard !expectingNavigation, !streams.isEmpty else { return }
        AppLogger.shared.log("🤖 [GeminiWeb] Trang tự điều hướng khi còn \(streams.count) fetch đang bay — huỷ để lượt sau thử lại")
        failAllStreams(.documentChanged)
    }

    /// Commit (và `didFinish` phòng khi commit không tới tay) đều mở khoá người chờ trong `load()`.
    func navigationDidCommitOrFinish() {
        expectingNavigation = false
        resumeNavigationWaiters()
    }

    func navigationDidFail(_ error: Error) {
        expectingNavigation = false
        AppLogger.shared.log("🤖 [GeminiWeb] Nạp trang thất bại: \(error.localizedDescription)")
        failNavigationWaiters(GeminiWebError.script(error.localizedDescription))
    }

    /// WebKit giết tiến trình nội dung (áp lực bộ nhớ): mọi stream đang bay coi như hỏng, lượt sau tạo lại.
    func contentProcessDidTerminate() {
        AppLogger.shared.log("🤖 [GeminiWeb] Tiến trình web bị kết thúc — giải phóng WKWebView ẩn")
        releaseWebView()
    }
}
