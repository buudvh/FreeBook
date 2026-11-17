import Foundation
import WebKit

/// Chủ sở hữu **duy nhất** của WKWebView ẩn chạy trang ChatGPT ẩn danh (`chatgpt.com`, 1.3.971).
///
/// - Cùng `WKWebsiteDataStore.default()` và cùng UA Safari iOS với trình duyệt bypass ⇒ bước kiểm tra Cloudflare người
///   dùng qua ở đó có hiệu lực ngay ở đây, và **đăng nhập ChatGPT ở đó thì ở đây chạy bằng tài khoản đó**; chưa đăng
///   nhập thì trang là bản ẩn danh. Hai kiểu trang khác cấu trúc — `ChatGPTWebPageContract` đọc được cả hai.
/// - Nằm trong một cửa sổ ẩn **riêng** (`GeminiWebHiddenWindowHost`) để WebKit không tạm dừng tiến trình web khi app ở
///   trước (bài học 1.3.507). **Không** gắn rule list chặn quảng cáo hay `WebContentPolicy`.
/// - Cuộc chat ẩn danh / chat tạm chỉ sống trong trang đang mở (nạp lại là mất) ⇒ sau một lượt **chat** thành công trang được giữ
///   `chatParkDelaySeconds` để lượt kế của **cùng phiên chat app** hỏi tiếp ngay trong trang (`liveSession`). Lượt quét,
///   ping, lượt lỗi, và mọi điều hướng mới đều bỏ `liveSession`.
/// - Hết thời gian giữ (hoặc lượt không giữ trang: sau `parkDelaySeconds`) ⇒ đưa trang về trang trắng: cửa sổ ẩn giữ
///   WebView ở trạng thái "hiển thị" nên trang để yên vẫn chạy JS và hẹn giờ (bài học nóng máy 1.3.963).
/// - Mỗi lượt cấp một mã (`beginTurn`); `abort(token:)` chỉ dừng trang khi mã còn là lượt hiện hành. Tự giải phóng
///   WebView sau 10 phút không có lượt nào.
/// - Log chỉ host + path. Mọi hàm chạy trên MainActor; `ChatGPTWebClient` (actor) gọi vào đây. Delegate WebKit:
///   `+Delegates.swift`.
@MainActor
final class ChatGPTWebSessionController: NSObject {
    static let shared = ChatGPTWebSessionController()

    private static let commitTimeout: TimeInterval = 30
    private static let idleReleaseSeconds: TimeInterval = 10 * 60
    /// Lượt không giữ trang: chờ chừng này rồi đưa trang về trắng.
    private static let parkDelaySeconds: TimeInterval = 3
    /// Lượt chat giữ trang để hỏi tiếp: quá chừng này không có lượt mới thì đưa trang về trắng (lượt sau mở cuộc chat mới
    /// với đủ ngữ cảnh).
    private static let chatParkDelaySeconds: TimeInterval = 180
    /// Chờ trang cập nhật ô nhập sau khi gán chữ.
    private static let fillSettleNanoseconds: UInt64 = 250_000_000

    private var webView: WKWebView?
    private let windowHost = GeminiWebHiddenWindowHost()
    private var navigationWaiters: [CheckedContinuation<Void, Error>] = []
    /// Điều hướng do `navigate(to:)` mở — commit của điều hướng khác (trang trắng lúc park) không mở khoá người chờ.
    private var expectedNavigation: WKNavigation?
    private var currentTurn: UUID?
    private var idleReleaseTask: Task<Void, Never>?
    private var parkTask: Task<Void, Never>?
    /// Trang đang mở còn giữ cuộc chat của phiên chat app nào (`nil` = không giữ).
    private(set) var liveSession: ChatGPTWebLiveSession?

    /// Kiểu trang lượt gần nhất gặp (`true` = đã đăng nhập, `false` = ẩn danh, `nil` = chưa có lượt nào trong lần mở app
    /// này hoặc vừa đổi tài khoản) — cho hàng tài khoản ở Cấu hình AI.
    private(set) var lastPageSignedIn: Bool?

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
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        parkTask?.cancel()
        parkTask = nil
        _ = ensureWebView()
        return token
    }

    /// `live` khác nil = lượt chat thành công, giữ trang cho lượt kế của phiên đó.
    func endTurn(token: UUID, live: ChatGPTWebLiveSession?) {
        guard currentTurn == token else { return }
        currentTurn = nil
        liveSession = live
        schedulePark(after: live == nil ? Self.parkDelaySeconds : Self.chatParkDelaySeconds)
        scheduleIdleRelease()
    }

    /// Người dùng bấm Dừng / app vào nền giữa lượt: đưa trang về trắng để ChatGPT không viết tiếp vào trang mà lượt sau
    /// dùng lại. Cuộc chat của trang mất theo — lượt sau mở cuộc chat mới với đủ ngữ cảnh.
    func abort(token: UUID) {
        guard currentTurn == token, let webView else { return }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Huỷ lượt — dừng trang (\(ChatGPTWebPageContract.describe(webView.url)))")
        liveSession = nil
        failNavigationWaiters(CancellationError())
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }

    func notePageKind(signedIn: Bool) {
        if lastPageSignedIn != signedIn {
            AppLogger.shared.log("🤖 [ChatGPTWeb] Trang ChatGPT là bản \(signedIn ? "đã đăng nhập" : "ẩn danh")")
        }
        lastPageSignedIn = signedIn
    }

    /// Tài khoản có thể vừa đổi (đăng xuất, hoặc người dùng vừa đóng tab ChatGPT của trình duyệt bypass): quên kiểu trang
    /// đã thấy và bỏ WebView ẩn để lượt sau nạp trang bằng cookie mới.
    func forgetAccountState() {
        lastPageSignedIn = nil
        guard currentTurn == nil else { return }
        releaseWebView()
    }

    // MARK: - Trang

    /// Điều hướng và chờ tới **commit** (HTML bắt đầu về), trần 30 s.
    func navigate(to url: URL) async throws {
        let webView = ensureWebView()
        windowHost.attach(webView)
        liveSession = nil
        let startedAt = Date()
        let timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.commitTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Trang ChatGPT không commit sau \(Int(Self.commitTimeout)) s \(GeminiWebForegroundGate.currentAppStateLabel)")
            self?.failNavigationWaiters(ChatGPTWebError.timeout)
        }
        defer { timeoutTask.cancel() }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            navigationWaiters.append(continuation)
            expectedNavigation = webView.load(URLRequest(url: url, timeoutInterval: Self.commitTimeout))
        }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Trang commit sau \(Self.ms(since: startedAt)) ms (\(ChatGPTWebPageContract.describe(webView.url)))")
    }

    func snapshot() async -> ChatGPTWebPageContract.Snapshot? {
        guard let webView else { return nil }
        guard let raw = try? await evaluate(ChatGPTWebPageContract.snapshotScript, in: webView) else { return nil }
        return ChatGPTWebPageContract.Snapshot(raw)
    }

    /// Gán chữ vào ô nhập rồi kiểm tra chữ đã thật sự nằm trong ô. Vùng soạn thảo của trang đã đăng nhập không nhận sự
    /// kiện `paste` ⇒ thử `execCommand('insertText')` một lần. `false` = không thấy ô nhập hoặc ô không nhận chữ.
    func fill(_ text: String) async -> Bool {
        guard let webView, let script = ChatGPTWebPageContract.fillComposerScript(text) else { return false }
        guard (try? await evaluate(script, in: webView)) as? Bool == true else { return false }
        try? await Task.sleep(nanoseconds: Self.fillSettleNanoseconds)
        if let filled = await snapshot(), filled.draftLength > 0 { return true }
        guard let fallback = ChatGPTWebPageContract.fillFallbackScript(text) else { return false }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Ô nhập chưa nhận chữ sau sự kiện paste — thử execCommand insertText")
        _ = try? await evaluate(fallback, in: webView)
        try? await Task.sleep(nanoseconds: Self.fillSettleNanoseconds)
        return (await snapshot()?.draftLength ?? 0) > 0
    }

    /// Gửi form của ô nhập.
    func submit() async -> ChatGPTWebPageContract.SubmitOutcome {
        guard let webView,
              let raw = (try? await evaluate(ChatGPTWebPageContract.submitScript, in: webView)) as? String,
              let outcome = ChatGPTWebPageContract.SubmitOutcome(rawValue: raw) else { return .noComposer }
        return outcome
    }

    // MARK: - WebView ẩn

    private func ensureWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.mediaTypesRequiringUserActionForPlayback = .all
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)
        view.customUserAgent = WebUserAgent.mobile
        view.navigationDelegate = self
        windowHost.attach(view)
        webView = view
        AppLogger.shared.log("🤖 [ChatGPTWeb] Tạo WKWebView ẩn")
        return view
    }

    func releaseWebView() {
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
        parkTask?.cancel()
        parkTask = nil
        liveSession = nil
        guard let view = webView else { return }
        view.navigationDelegate = nil
        view.stopLoading()
        windowHost.detach(view)
        webView = nil
        expectedNavigation = nil
        failNavigationWaiters(ChatGPTWebError.webViewUnavailable)
    }

    /// Đưa trang về trắng khi không còn lượt nào (giữ WebView + tiến trình web để lượt sau không phải dựng lại). Lượt mới
    /// bắt đầu trong lúc chờ ⇒ `beginTurn` huỷ. Trang đã trắng (vừa `abort`) ⇒ bỏ qua.
    private func schedulePark(after seconds: TimeInterval) {
        parkTask?.cancel()
        parkTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.currentTurn == nil, let webView = self.webView else { return }
            self.liveSession = nil
            guard let url = webView.url, url.absoluteString != "about:blank" else { return }
            AppLogger.shared.log("🤖 [ChatGPTWeb] Hết \(Int(seconds)) s không có lượt mới — đưa trang ẩn về trang trắng (\(ChatGPTWebPageContract.describe(url)))")
            webView.stopLoading()
            webView.loadHTMLString("", baseURL: nil)
        }
    }

    private func scheduleIdleRelease() {
        idleReleaseTask?.cancel()
        idleReleaseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Self.idleReleaseSeconds * 1_000_000_000))
            guard !Task.isCancelled, let self, self.webView != nil, self.currentTurn == nil else { return }
            AppLogger.shared.log("🤖 [ChatGPTWeb] Giải phóng WKWebView ẩn sau \(Int(Self.idleReleaseSeconds)) s không dùng")
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
                    continuation.resume(throwing: ChatGPTWebError.protocolChanged("JavaScript: \(error.localizedDescription)"))
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
        AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Nạp trang ChatGPT thất bại \(GeminiWebForegroundGate.currentAppStateLabel): \(error.localizedDescription)")
        failNavigationWaiters(ChatGPTWebError.pageLoadFailed(error.localizedDescription))
    }

    func contentProcessDidTerminate() {
        AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Tiến trình web bị kết thúc — giải phóng WKWebView ẩn")
        releaseWebView()
    }
}
