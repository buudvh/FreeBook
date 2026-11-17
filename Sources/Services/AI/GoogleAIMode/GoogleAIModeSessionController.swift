import Foundation
import WebKit

/// Chủ sở hữu **duy nhất** của WKWebView ẩn chạy Chế độ AI của Google (`google.com/search?udm=50`, 1.3.609).
///
/// - Cùng `WKWebsiteDataStore.default()` với Gemini Web và trình duyệt bypass ⇒ đã đăng nhập Google ở đó thì chạy theo
///   tài khoản đó, chưa thì ẩn danh; captcha giải trong trình duyệt bypass có hiệu lực ngay ở đây.
/// - Nằm trong một cửa sổ ẩn **riêng** (`GeminiWebHiddenWindowHost`) để WebKit không tạm dừng tiến trình web khi app ở
///   trước (bài học 1.3.507). UA Safari iOS như Gemini Web.
/// - **Không** gắn rule list chặn quảng cáo hay `WebContentPolicy`: Google ngoài phạm vi chặn quảng cáo, bộ lọc có thể
///   làm hỏng trang.
/// - Trang `/sorry` (Google nghi bot) hoặc HTTP 429 ⇒ chặn điều hướng, đánh dấu `verificationRequired`; HTTP 413 ⇒
///   `requestTooLong`.
/// - Mỗi lượt cấp một mã (`beginTurn`); `abort(token:)` chỉ dừng trang khi mã còn là lượt hiện hành — lệnh huỷ đến trễ
///   không giết lượt của truyện khác. Tự giải phóng WebView sau 10 phút không có lượt nào.
/// - Lượt xong ⇒ sau `parkDelaySeconds` đưa trang về trang trắng (`schedulePark`, 1.3.963): cửa sổ ẩn giữ WebView ở trạng
///   thái "hiển thị" nên trang Google để yên vẫn chạy JS, hẹn giờ, hoạt ảnh và vẽ lại — nguồn nóng máy giữa các lượt.
///   Lượt nào cũng điều hướng lại từ đầu (lượt mới ⇒ URL câu hỏi, nối tiếp ⇒ URL khôi phục `mstk`) nên không mất gì.
/// - Log chỉ host + path: URL mang cả chương truyện và `mstk`. Mọi hàm chạy trên MainActor; `GoogleAIModeClient` (actor)
///   gọi vào đây. Delegate WebKit: `+Delegates.swift`.
@MainActor
final class GoogleAIModeSessionController: NSObject {
    static let shared = GoogleAIModeSessionController()

    private static let commitTimeout: TimeInterval = 30
    private static let idleReleaseSeconds: TimeInterval = 10 * 60
    /// Chờ chừng này sau lượt rồi mới đưa trang về trắng — để các request cuối của trang (lưu cuộc chat, xoay cookie) xong.
    private static let parkDelaySeconds: TimeInterval = 3

    private var webView: WKWebView?
    private let windowHost = GeminiWebHiddenWindowHost()
    private var navigationWaiters: [CheckedContinuation<Void, Error>] = []
    /// Điều hướng do `navigate(to:)` mở — commit của điều hướng khác (trang tự chuyển) không mở khoá người chờ.
    private var expectedNavigation: WKNavigation?
    private var currentTurn: UUID?
    private var idleReleaseTask: Task<Void, Never>?
    private var parkTask: Task<Void, Never>?
    /// Đã gặp trang xác minh kể từ lúc lượt hiện tại bắt đầu — kể cả khi chính trang tự chuyển sang đó lúc đang trả lời.
    private(set) var verificationRequired = false

    var hasWebView: Bool { webView != nil }
    /// Đang có lượt chạy — bối cảnh cho log `MainThreadHangMonitor`.
    var isTurnActive: Bool { currentTurn != nil }

    private override init() {
        super.init()
    }

    // MARK: - Lượt

    func beginTurn() -> UUID {
        let token = UUID()
        currentTurn = token
        verificationRequired = false
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        parkTask?.cancel()
        parkTask = nil
        _ = ensureWebView()
        return token
    }

    func endTurn(token: UUID) {
        guard currentTurn == token else { return }
        currentTurn = nil
        schedulePark()
        scheduleIdleRelease()
    }

    /// Người dùng bấm Dừng / app vào nền giữa lượt: dừng trang để Google không viết tiếp vào trang mà lượt sau dùng lại.
    func abort(token: UUID) {
        guard currentTurn == token, let webView else { return }
        AppLogger.shared.log("🤖 [AIMode] Huỷ lượt — dừng trang (\(GoogleAIModePageContract.describe(webView.url)))")
        failNavigationWaiters(CancellationError())
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    // MARK: - Trang

    /// Điều hướng và chờ tới **commit** (HTML bắt đầu về), trần 30 s.
    func navigate(to url: URL) async throws {
        let webView = ensureWebView()
        windowHost.attach(webView)
        let startedAt = Date()
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.commitTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            AppLogger.shared.log("❌ 🤖 [AIMode] Trang Google không commit sau \(Int(Self.commitTimeout)) s \(GeminiWebForegroundGate.currentAppStateLabel)")
            self?.failNavigationWaiters(GoogleAIModeError.timeout)
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationWaiters.append(continuation)
            expectedNavigation = webView.load(URLRequest(url: url, timeoutInterval: Self.commitTimeout))
        }
        AppLogger.shared.log("🤖 [AIMode] Trang commit sau \(Self.ms(since: startedAt)) ms (\(GoogleAIModePageContract.describe(webView.url)))")
        if verificationRequired { throw GoogleAIModeError.captchaRequired }
    }

    func snapshot() async -> GoogleAIModePageContract.Snapshot? {
        guard let webView else { return nil }
        guard let raw = try? await evaluate(GoogleAIModePageContract.snapshotScript, in: webView) else { return nil }
        return GoogleAIModePageContract.Snapshot(raw)
    }

    /// Gán chữ vào ô nhập, chờ trang bật nút gửi, rồi nhấn Enter. `false` = không thấy ô nhập.
    func submit(_ text: String) async -> Bool {
        guard let webView, let fill = GoogleAIModePageContract.fillComposerScript(text) else { return false }
        guard (try? await evaluate(fill, in: webView)) as? Bool == true else { return false }
        try? await Task.sleep(nanoseconds: 300_000_000)
        return (try? await evaluate(GoogleAIModePageContract.pressEnterScript, in: webView)) as? Bool == true
    }

    func clickSend() async -> Bool {
        guard let webView else { return false }
        return (try? await evaluate(GoogleAIModePageContract.clickSendScript, in: webView)) as? Bool == true
    }

    // MARK: - WebView ẩn

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.customUserAgent = GeminiWebSessionController.userAgent
        view.navigationDelegate = self
        windowHost.attach(view)
        webView = view
        AppLogger.shared.log("🤖 [AIMode] Tạo WKWebView ẩn")
        return view
    }

    func releaseWebView() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        parkTask?.cancel()
        parkTask = nil
        guard let view = webView else { return }
        view.navigationDelegate = nil
        view.stopLoading()
        windowHost.detach(view)
        webView = nil
        expectedNavigation = nil
        failNavigationWaiters(GoogleAIModeError.webViewUnavailable)
    }

    /// Đưa trang về trắng khi không còn lượt nào (giữ WebView + tiến trình web để lượt sau không phải dựng lại). Lượt mới
    /// bắt đầu trong lúc chờ ⇒ `beginTurn` huỷ. Trang đã trắng (vừa `abort`) ⇒ bỏ qua.
    private func schedulePark() {
        parkTask?.cancel()
        parkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.parkDelaySeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.currentTurn == nil, let webView = self.webView else { return }
            guard let url = webView.url, url.absoluteString != "about:blank" else { return }
            AppLogger.shared.log("🤖 [AIMode] Lượt xong — đưa trang ẩn về trang trắng (\(GoogleAIModePageContract.describe(url)))")
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    private func scheduleIdleRelease() {
        idleReleaseTask?.cancel()
        idleReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleReleaseSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.webView != nil, self.currentTurn == nil else { return }
            AppLogger.shared.log("🤖 [AIMode] Giải phóng WKWebView ẩn sau \(Int(Self.idleReleaseSeconds)) s không dùng")
            self.releaseWebView()
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

    private func evaluate(_ script: String, in webView: WKWebView) async throws -> Any? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any?, Error>) in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: GoogleAIModeError.protocolChanged("JavaScript: \(error.localizedDescription)"))
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }

    // MARK: - Sự kiện điều hướng (gọi từ `+Delegates.swift`)

    func navigationDidCommit(_ navigation: WKNavigation?) {
        guard expectedNavigation == nil || navigation === expectedNavigation else { return }
        expectedNavigation = nil
        resumeNavigationWaiters()
    }

    /// Huỷ do điều hướng mới thay thế (`NSURLErrorCancelled`) hay do chính app chặn (`WebKitErrorDomain` 102) thì bỏ
    /// qua: người chờ đã được xử lý ở nơi khác hoặc điều hướng thay thế sẽ commit.
    func navigationDidFail(_ navigation: WKNavigation?, error: Error) {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return }
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return }
        guard expectedNavigation == nil || navigation === expectedNavigation else { return }
        expectedNavigation = nil
        AppLogger.shared.log("❌ 🤖 [AIMode] Nạp trang Google thất bại \(GeminiWebForegroundGate.currentAppStateLabel): \(error.localizedDescription)")
        failNavigationWaiters(GoogleAIModeError.pageLoadFailed(error.localizedDescription))
    }

    /// `true` = chặn điều hướng này (trang xác minh của Google).
    func shouldBlockNavigation(to url: URL?) -> Bool {
        guard GoogleAIModePageContract.isVerificationPage(url) else { return false }
        markVerificationRequired(reason: "chuyển sang \(GoogleAIModePageContract.describe(url))")
        return true
    }

    /// `true` = chặn phản hồi này: 429 (captcha) hoặc 413 (câu hỏi quá dài).
    func shouldBlockResponse(status: Int, url: URL?) -> Bool {
        if status == 429 || GoogleAIModePageContract.isVerificationPage(url) {
            markVerificationRequired(reason: "HTTP \(status) \(GoogleAIModePageContract.describe(url))")
            return true
        }
        if status == 413 {
            AppLogger.shared.log("❌ 🤖 [AIMode] Google trả HTTP 413 — câu hỏi quá dài")
            failNavigationWaiters(GoogleAIModeError.requestTooLong)
            return true
        }
        return false
    }

    func contentProcessDidTerminate() {
        AppLogger.shared.log("❌ 🤖 [AIMode] Tiến trình web bị kết thúc — giải phóng WKWebView ẩn")
        releaseWebView()
    }

    private func markVerificationRequired(reason: String) {
        AppLogger.shared.log("❌ 🤖 [AIMode] Google yêu cầu xác minh (captcha): \(reason) \(GeminiWebForegroundGate.currentAppStateLabel)")
        verificationRequired = true
        failNavigationWaiters(GoogleAIModeError.captchaRequired)
    }
}
