import SwiftUI
import UIKit
import Combine

/// Điều phối toàn cục cho các tác vụ AI Agent: quản lý tác vụ ngầm, trạng thái phiên làm việc,
/// thông báo Toast khi hoàn thành ngoài màn hình và cơ chế present toàn màn hình ở mọi nơi trong app.
///
/// Từ 1.3.558 mọi trạng thái chạy khoá theo `bookId` (`runs`): mỗi truyện một tác vụ riêng, truyện B chat/quét được
/// trong lúc truyện A đang quét. Vòng đời một lượt theo truyện nằm ở `+BookRuns.swift`.
@MainActor
public final class AIRuntimeCoordinator: ObservableObject {
    public static let shared = AIRuntimeCoordinator()

    /// Ngữ cảnh sách và chương đang được AI phục vụ.
    public struct ActiveContext: Equatable {
        public let bookId: String
        public let bookTitle: String
        public let chapterIndex: Int
        public let chapterTitle: String
        public let currentChapterRawContent: String
        /// Cấu hình dịch Reader đang áp cho truyện (1.3.603) — sheet quét tên riêng dịch tên chương theo đúng nó.
        public let translatesChapterTitles: Bool
        public let convertsTraditionalToSimplified: Bool

        public init(
            bookId: String,
            bookTitle: String,
            chapterIndex: Int,
            chapterTitle: String,
            currentChapterRawContent: String,
            translatesChapterTitles: Bool = false,
            convertsTraditionalToSimplified: Bool = false
        ) {
            self.bookId = bookId
            self.bookTitle = bookTitle
            self.chapterIndex = chapterIndex
            self.chapterTitle = chapterTitle
            self.currentChapterRawContent = currentChapterRawContent
            self.translatesChapterTitles = translatesChapterTitles
            self.convertsTraditionalToSimplified = convertsTraditionalToSimplified
        }
    }

    /// Trạng thái AI theo truyện. Stream ghi vào đây mỗi ≥ 50 ms ⇒ ai nghe phải lọc đúng truyện của mình và chỉ gán
    /// khi giá trị đổi (màn AI), hoặc `map` về bản tóm tắt nhỏ rồi `removeDuplicates` (nút nổi).
    /// Setter `internal` (không `private`) vì các luồng chạy nằm ở `+BookRuns`/`+BatchExtraction`/`+NameScanRetry`.
    @Published public internal(set) var runs: [String: AIBookRunState] = [:]
    /// `bookId` của màn AI đang mở (`nil` = không có màn AI nào). Thay cờ Bool cũ: truyện A xong trong lúc màn AI của
    /// truyện B đang mở vẫn phải có toast cho A.
    @Published public var presentedAIBookId: String? = nil
    /// `bookId` của Reader đang trên màn hình (`nil` khi không có Reader nào). Là **bookId** chứ không
    /// phải cờ Bool: widget thu nhỏ của truyện A bấm khi đang đọc truyện B phải mở lại AI của **A**,
    /// không được nhờ Reader B dựng màn AI theo truyện của nó.
    public var activeReaderBookId: String? = nil

    /// Tác vụ đang bay và mã lượt hiện hành của từng truyện. Mỗi truyện chỉ một tác vụ tại một thời điểm nên một mã
    /// lượt là đủ (thay cặp mã stream/batch toàn cục trước 1.3.558). Mọi cập nhật trễ — nhịp chữ của stream, báo tiến
    /// độ batch chạy trong một `Task` mới (không bị huỷ theo) — phải khớp mã này, nếu không thì bỏ (1.3.515).
    var tasks: [String: Task<Void, Never>] = [:]
    var runIds: [String: UUID] = [:]
    var nameScanRetryContexts: [String: NameScanRetryContext] = [:]
    var lastSessionIds: [String: UUID] = [:]
    /// Ngữ cảnh mở màn AI theo truyện — nút nổi mở đúng màn AI của truyện được chạm. Chỉ giữ truyện còn entry trong
    /// `runs` và truyện mở AI gần nhất (`pruneContexts`), vì ngữ cảnh mang cả nội dung chương.
    private var contexts: [String: ActiveContext] = [:]
    private var latestContextBookId: String? = nil
    private var cancellables = Set<AnyCancellable>()
    private weak var currentPresentedVC: UIViewController? = nil

    static let chatTaskTitle = "AI đang suy nghĩ"

    private init() {
        setupTTSObservers()
    }

    /// Lắng nghe các notification điều hướng từ TTS để tự động đóng màn hình AI an toàn.
    private func setupTTSObservers() {
        NotificationCenter.default.publisher(for: NSNotification.Name("openCurrentlyPlayingReader"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dismissFullScreen(animated: true)
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("navigateReaderToPlayingChapter"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.dismissFullScreen(animated: true)
            }
            .store(in: &cancellables)
    }

    /// Đặt ngữ cảnh của truyện vừa mở màn AI.
    public func updateContext(_ context: ActiveContext) {
        contexts[context.bookId] = context
        latestContextBookId = context.bookId
    }

    /// Bỏ ngữ cảnh của truyện đã rảnh, trừ truyện mở AI gần nhất.
    func pruneContexts() {
        contexts = contexts.filter { runs[$0.key] != nil || $0.key == latestContextBookId }
    }

    // MARK: - Quản lý tác vụ ngầm

    /// Bắt đầu streaming phản hồi hội thoại cho một truyện — chỉ thay tác vụ cũ của **chính truyện đó**.
    public func startChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        session: AIChatSession,
        bookId: String,
        bookTitle: String,
        assistantMsgId: UUID,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        let runId = beginRun(bookId: bookId, bookTitle: bookTitle, taskTitle: Self.chatTaskTitle, session: session)

        tasks[bookId] = Task { [weak self] in
            do {
                let stream: AsyncThrowingStream<String, Error>
                if config.activeProfile.isGeminiWeb {
                    // Nối tiếp một cuộc chat Gemini cho mỗi phiên chat của app (1.3.514).
                    stream = await GeminiWebClient.shared.sendConversationStreaming(
                        config: config,
                        messages: messages,
                        sessionId: session.id
                    )
                } else if config.activeProfile.apiFormat == "anthropic" {
                    stream = await AnthropicClient.shared.sendChatStreaming(config: config, messages: messages)
                } else {
                    stream = await OpenAIClient.shared.sendChatStreaming(config: config, messages: messages)
                }
                var accumulated = ""
                var lastUIUpdateTime: TimeInterval = 0
                for try await delta in stream {
                    guard !Task.isCancelled else { break }
                    accumulated += delta
                    let now = Date().timeIntervalSinceReferenceDate
                    if now - lastUIUpdateTime >= 0.05 {
                        lastUIUpdateTime = now
                        let stillCurrent = await MainActor.run { () -> Bool in
                            guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return false }
                            self.updateMessage(assistantMsgId, bookId: bookId) { $0.content = accumulated }
                            return true
                        }
                        guard stillCurrent else { break }
                        onDelta(accumulated)
                    }
                }

                guard !Task.isCancelled else { return }

                // Phản hồi rỗng là lỗi, không phải hoàn tất: tin trợ lý rỗng bị màn AI ẩn đi, người dùng
                // sẽ không thấy gì (lỗi thật 1.3.506). Ném để rơi vào nhánh `catch` bên dưới.
                let providerName = config.activeProfile.name
                guard !accumulated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw AIEmptyResponseError(providerName: providerName)
                }
                AppLogger.shared.log("🤖 [AI] \(providerName) trả lời xong, \(accumulated.count) ký tự")
                onComplete(accumulated)

                await MainActor.run {
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    self.updateMessage(assistantMsgId, bookId: bookId) {
                        $0.content = accumulated
                        $0.isStreaming = false
                    }
                    self.saveRunSession(bookId: bookId)
                    let toast = self.toastText("AI đã hoàn tất phản hồi!", bookId: bookId, bookTitle: bookTitle)
                    let isPresented = self.presentedAIBookId == bookId
                    self.endRun(bookId: bookId)
                    if !isPresented {
                        ToastManager.shared.show(message: toast, type: .success)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.shared.log("❌ 🤖 [AI] \(config.activeProfile.name) lỗi: \(error.localizedDescription)")
                onError(error.localizedDescription)
                await MainActor.run {
                    guard let self = self, self.isCurrentRun(runId, bookId: bookId) else { return }
                    self.updateMessage(assistantMsgId, bookId: bookId) {
                        $0.content = "Lỗi phản hồi: \(error.localizedDescription)"
                        $0.isStreaming = false
                    }
                    self.saveRunSession(bookId: bookId)
                    let toast = self.toastText("AI phản hồi thất bại.", bookId: bookId, bookTitle: bookTitle)
                    let isPresented = self.presentedAIBookId == bookId
                    self.endRun(bookId: bookId)
                    if !isPresented {
                        ToastManager.shared.show(message: toast, type: .error)
                    }
                }
            }
        }
    }

    // MARK: - Mở màn hình toàn màn hình từ bất kỳ đâu

    /// Mở màn hình AI toàn màn hình của một truyện (nút nổi gọi với truyện được chạm) từ ViewController cao nhất
    /// tầng `.normal`.
    public func presentFullScreen(bookId: String) {
        guard let ctx = contexts[bookId] else {
            AppLogger.shared.log("❌ 🤖 [AI] Không có ngữ cảnh để mở màn AI của truyện \(bookId)")
            return
        }
        guard presentedAIBookId == nil else { return }

        // Chỉ nhờ Reader mở lại bằng `.fullScreenCover` khi Reader đang hiển thị đúng là truyện đang
        // chạy AI. Reader của truyện khác (hoặc Shelf/Discovery) đi đường UIKit `.overFullScreen` bên
        // dưới với ngữ cảnh của truyện đang chạy — không tháo view hierarchy của Reader đó.
        if activeReaderBookId == ctx.bookId {
            NotificationCenter.default.post(
                name: NSNotification.Name("reopenReaderAI"),
                object: nil,
                userInfo: ["bookId": ctx.bookId]
            )
            return
        }

        guard let topVC = findTopViewController() else { return }
        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentFullScreen(bookId: bookId)
            }
            return
        }

        let aiView = ReaderAIFullScreenView(
            bookId: ctx.bookId,
            bookTitle: ctx.bookTitle,
            chapterIndex: ctx.chapterIndex,
            chapterTitle: ctx.chapterTitle,
            currentChapterRawContent: ctx.currentChapterRawContent,
            translatesChapterTitles: ctx.translatesChapterTitles,
            convertsTraditionalToSimplified: ctx.convertsTraditionalToSimplified
        )

        let hosting = UIHostingController(rootView: aiView)
        hosting.modalPresentationStyle = .overFullScreen
        self.currentPresentedVC = hosting
        self.presentedAIBookId = ctx.bookId

        topVC.present(hosting, animated: true, completion: nil)
    }

    /// Đóng màn hình AI toàn màn hình (bản mở bằng UIKit) nếu đang mở.
    public func dismissFullScreen(animated: Bool = true) {
        guard let presentedVC = currentPresentedVC else { return }
        presentedVC.dismiss(animated: animated) { [weak self] in
            self?.presentedAIBookId = nil
            self?.currentPresentedVC = nil
        }
    }

    /// Tìm ViewController cao nhất thuộc window `.normal` để không tranh chấp với UIWindow của widget nổi.
    private func findTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }

        guard let window = windowScene.windows.first(where: { $0.isKeyWindow && $0.windowLevel == .normal })
                ?? windowScene.windows.first(where: { $0.windowLevel == .normal }),
              let rootVC = window.rootViewController else {
            return nil
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}
