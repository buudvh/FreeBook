import Foundation
import WebKit

/// Chủ sở hữu **duy nhất** của WKWebView ẩn đã đăng nhập gemini.google.com, và là nơi duy nhất chạy
/// giao thức web của Gemini — bằng `fetch()` **trong chính trang đó**.
///
/// Vì sao không copy cookie sang `URLSession`: `__Secure-1PSIDTS` là cookie HttpOnly xoay liên tục,
/// và Google gắn phiên với dấu vân tay trình duyệt (thư viện Python tham chiếu phải giả lập Chrome 145
/// để né *Device Bound Session Credentials*). Để WebKit tự lo cookie, Origin/Referer và TLS thì app
/// chỉ còn phải dựng body + header và đọc stream.
///
/// WebView **không gắn vào window** (giống `WebViewLoader` bypass Cloudflare) nhưng dùng
/// `WKWebsiteDataStore.default()` — cùng kho cookie với `GeminiWebLoginView`, nên đăng nhập xong là
/// `prepare(force: true)` dùng được ngay. Mọi hàm chạy trên MainActor vì WebKit yêu cầu;
/// `GeminiWebClient` (actor) gọi vào đây rồi bóc frame ở ngoài. WebView được giải phóng sau 10 phút
/// không dùng và tạo lại khi cần.
@MainActor
final class GeminiWebSessionController: NSObject {
    static let shared = GeminiWebSessionController()

    /// UA Safari iOS — cùng chuỗi với trình duyệt bypass; Google từ chối đăng nhập khi nhận ra WebView nhúng.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private static let messageHandlerName = "geminiWebStream"
    private static let navigationTimeout: TimeInterval = 30
    /// 20 lần × 0,5 s = 10 s chờ `WIZ_global_data` xuất hiện sau `didFinish`.
    private static let tokenProbeAttempts = 20
    private static let idleReleaseSeconds: TimeInterval = 10 * 60
    private static let probeScript = """
    (function () {
      var w = window.WIZ_global_data || null;
      return {
        hasWiz: !!w,
        token: (w && w.SNlM0e) || "",
        bl: (w && w.cfb2h) || "",
        sid: (w && w.FdrFJe) || "",
        hl: (w && w.TuX5cc) || "",
        href: String(location.href)
      };
    })();
    """

    private var webView: WKWebView?
    private var initSession: GeminiWebInitSession?
    private var navigationWaiters: [CheckedContinuation<Void, Error>] = []
    private var streams: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
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

    /// Nạp (hoặc dùng lại) phiên: trang `/app` đã nạp và `WIZ_global_data` có token. Các lời gọi đồng
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
            let webView = self.ensureWebView()
            try await self.load(GeminiWebRequestBuilder.appURL, in: webView)
            let session = try await self.probeInitSession(in: webView)
            self.initSession = session
            self.touch()
            AppLogger.shared.log("🤖 [GeminiWeb] Phiên sẵn sàng (hl=\(session.language), bl=\(session.buildLabel ?? "-"))")
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
    func fetchStream(_ request: GeminiWebRequestBuilder.Request, timeout: TimeInterval = 90) -> AsyncThrowingStream<String, Error> {
        let id = UUID().uuidString
        return AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                guard let self, let webView = self.webView, self.initSession != nil else {
                    continuation.finish(throwing: GeminiWebError.sessionUnavailable)
                    return
                }
                self.streams[id] = continuation
                self.touch()

                let timeoutTask = Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    guard !Task.isCancelled else { return }
                    self?.finishStream(id: id, error: GeminiWebError.timeout)
                }
                continuation.onTermination = { [weak self] _ in
                    timeoutTask.cancel()
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
                } catch {
                    self.finishStream(id: id, error: error)
                }
            }
        }
    }

    private func handleScriptMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let id = dict["id"] as? String else { return }
        let type = dict["type"] as? String ?? ""
        let payload = dict["payload"] as? String ?? ""
        switch type {
        case "chunk":
            if !payload.isEmpty { streams[id]?.yield(payload) }
        case "done":
            finishStream(id: id, error: nil)
        case "error":
            finishStream(id: id, error: Self.scriptError(from: payload))
        default:
            break
        }
    }

    private static func scriptError(from payload: String) -> GeminiWebError {
        if payload.hasPrefix("HTTP ") {
            let digits = payload.dropFirst(5).prefix { $0.isNumber }
            if let status = Int(digits) { return .http(status) }
        }
        return .script(String(payload.prefix(200)))
    }

    private func finishStream(id: String, error: Error?) {
        guard let continuation = streams.removeValue(forKey: id) else { return }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }

    /// Consumer dừng sớm (đổi chương, huỷ chat): huỷ `fetch` tương ứng trong trang.
    private func abortScript(id: String) {
        streams.removeValue(forKey: id)
        guard let webView, let idLiteral = try? Self.jsLiteral(id) else { return }
        let script = "(function(){try{var c=window.__fbGeminiAbort&&window.__fbGeminiAbort[\(idLiteral)];if(c){c.abort();}}catch(e){}return true;})();"
        webView.evaluateJavaScript(script, completionHandler: nil)
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
        for id in Array(streams.keys) {
            finishStream(id: id, error: GeminiWebError.sessionUnavailable)
        }
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

    private func load(_ url: URL, in webView: WKWebView) async throws {
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.navigationTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.failNavigationWaiters(GeminiWebError.timeout)
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationWaiters.append(continuation)
            webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: Self.navigationTimeout))
        }
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

    /// Đọc `WIZ_global_data` sau khi trang nạp; app Gemini dựng bằng JS nên thử lại vài lần.
    private func probeInitSession(in webView: WKWebView) async throws -> GeminiWebInitSession {
        var sawWizWithoutToken = 0
        for _ in 0..<Self.tokenProbeAttempts {
            if let host = webView.url?.host?.lowercased(), host.contains("accounts.google.com") {
                throw GeminiWebError.notSignedIn
            }
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
                    if sawWizWithoutToken >= 4 { throw GeminiWebError.notSignedIn }
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }
        throw GeminiWebError.protocolChanged("trang /app không có WIZ_global_data.SNlM0e sau 10 s")
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

    // MARK: - JavaScript

    /// JSON là tập con của JS, trừ U+2028/U+2029 — thoát hai ký tự đó để chuỗi an toàn trong mọi engine.
    private static func jsLiteral(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        guard let text = String(data: data, encoding: .utf8) else {
            throw GeminiWebError.protocolChanged("không mã hoá được request sang JSON")
        }
        return text
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    /// `fetch` + `ReadableStream` trong trang; mỗi chunk đã giải mã UTF-8 được đẩy về Swift qua message handler.
    private static func fetchScript(id: String, request: GeminiWebRequestBuilder.Request) throws -> String {
        let idLiteral = try jsLiteral(id)
        let urlLiteral = try jsLiteral(request.url)
        let headersLiteral = try jsLiteral(request.headers)
        let fieldsLiteral = try jsLiteral(request.fields)
        return """
        (function () {
          var id = \(idLiteral), url = \(urlLiteral), headers = \(headersLiteral), fields = \(fieldsLiteral);
          var post = function (type, payload) {
            try {
              window.webkit.messageHandlers.\(messageHandlerName).postMessage({ id: id, type: type, payload: payload == null ? "" : String(payload) });
            } catch (e) {}
          };
          (async function () {
            try {
              var params = new URLSearchParams();
              for (var key in fields) {
                if (Object.prototype.hasOwnProperty.call(fields, key)) { params.append(key, fields[key]); }
              }
              var controller = new AbortController();
              window.__fbGeminiAbort = window.__fbGeminiAbort || {};
              window.__fbGeminiAbort[id] = controller;
              var response = await fetch(url, { method: "POST", headers: headers, body: params, credentials: "include", signal: controller.signal });
              if (!response.ok) {
                var detail = "";
                try { detail = (await response.text()).slice(0, 300); } catch (e) {}
                post("error", "HTTP " + response.status + " " + detail);
                return;
              }
              var reader = response.body.getReader();
              var decoder = new TextDecoder("utf-8");
              while (true) {
                var step = await reader.read();
                if (step.done) { break; }
                post("chunk", decoder.decode(step.value, { stream: true }));
              }
              post("chunk", decoder.decode());
              post("done", "");
            } catch (e) {
              post("error", String(e && e.message ? e.message : e));
            } finally {
              try { delete window.__fbGeminiAbort[id]; } catch (e) {}
            }
          })();
          return "started";
        })();
        """
    }
}

// MARK: - WKScriptMessageHandler

extension GeminiWebSessionController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        handleScriptMessage(message.body)
    }
}

// MARK: - WKNavigationDelegate

extension GeminiWebSessionController: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        resumeNavigationWaiters()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failNavigationWaiters(GeminiWebError.script(error.localizedDescription))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failNavigationWaiters(GeminiWebError.script(error.localizedDescription))
    }

    /// WebKit giết tiến trình nội dung (áp lực bộ nhớ): mọi stream đang bay coi như hỏng, lượt sau tạo lại.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        AppLogger.shared.log("🤖 [GeminiWeb] Tiến trình web bị kết thúc — giải phóng WKWebView ẩn")
        releaseWebView()
    }
}
