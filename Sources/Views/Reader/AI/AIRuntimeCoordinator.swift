import SwiftUI
import UIKit
import Combine

/// Điều phối toàn cục cho các tác vụ AI Agent: quản lý tác vụ ngầm, trạng thái phiên làm việc,
/// thông báo Toast khi hoàn thành ngoài màn hình và cơ chế present toàn màn hình ở mọi nơi trong app.
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

        public init(
            bookId: String,
            bookTitle: String,
            chapterIndex: Int,
            chapterTitle: String,
            currentChapterRawContent: String
        ) {
            self.bookId = bookId
            self.bookTitle = bookTitle
            self.chapterIndex = chapterIndex
            self.chapterTitle = chapterTitle
            self.currentChapterRawContent = currentChapterRawContent
        }
    }

    /// Setter `internal` (không `private`) vì luồng quét nằm ở `AIRuntimeCoordinator+BatchExtraction.swift`.
    @Published public internal(set) var isRunning: Bool = false
    @Published public internal(set) var activeTaskTitle: String = "AI đang suy nghĩ"
    @Published public var isFullScreenPresented: Bool = false
    @Published public private(set) var activeContext: ActiveContext? = nil
    @Published public var activeSessionId: UUID? = nil
    @Published public var activeSession: AIChatSession? = nil
    @Published public var batchProgress: AINameScanProgress? = nil
    @Published public var batchExtractedNames: [AIExtractedName] = []
    /// `bookId` của Reader đang trên màn hình (`nil` khi không có Reader nào). Là **bookId** chứ không
    /// phải cờ Bool: widget thu nhỏ của truyện A bấm khi đang đọc truyện B phải mở lại AI của **A**,
    /// không được nhờ Reader B dựng màn AI theo truyện của nó.
    public var activeReaderBookId: String? = nil

    private var activeStreamingTask: Task<Void, Never>? = nil
    var activeBatchTask: Task<Void, Never>? = nil
    /// Mã của lần chạy hiện hành (1.3.515). Mọi cập nhật trễ — nhịp chữ của stream, báo tiến độ batch chạy trong
    /// một `Task` mới (không bị huỷ theo) — phải khớp mã này, nếu không thì bỏ: trước đây chúng dựng lại dải batch
    /// và dòng "đang suy nghĩ" sau khi người dùng đã bấm dừng.
    private var streamRunId: UUID?
    var batchRunId: UUID?
    private var activeSingleTask: Task<Void, Never>? = nil
    private var cancellables = Set<AnyCancellable>()
    private weak var currentPresentedVC: UIViewController? = nil

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

    /// Đặt ngữ cảnh sách hiện thời cho AI.
    public func updateContext(_ context: ActiveContext) {
        self.activeContext = context
    }

    // MARK: - Quản lý tác vụ ngầm

    /// Bắt đầu streaming phản hồi hội thoại.
    public func startChatStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        session: AIChatSession,
        bookId: String,
        assistantMsgId: UUID,
        onDelta: @escaping (String) -> Void,
        onComplete: @escaping (String) -> Void,
        onError: @escaping (String) -> Void
    ) {
        cancelActiveTask()
        isRunning = true
        activeTaskTitle = "AI đang suy nghĩ"
        activeSessionId = session.id
        activeSession = session
        let runId = UUID()
        streamRunId = runId

        activeStreamingTask = Task { [weak self] in
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
                            guard let self = self, self.streamRunId == runId else { return false }
                            if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.activeSession?.messages[idx].content = accumulated
                            }
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
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeStreamingTask = nil
                    if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.activeSession?.messages[idx].content = accumulated
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "AI đã hoàn tất phản hồi!", type: .success)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLogger.shared.log("❌ 🤖 [AI] \(config.activeProfile.name) lỗi: \(error.localizedDescription)")
                onError(error.localizedDescription)
                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeStreamingTask = nil
                    if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        self.activeSession?.messages[idx].content = "Lỗi phản hồi: \(error.localizedDescription)"
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "AI phản hồi thất bại.", type: .error)
                    }
                }
            }
        }
    }

    /// Huỷ tác vụ AI đang thực thi (dùng nội bộ khi bắt đầu tác vụ mới — **không** đụng tin nhắn).
    public func cancelActiveTask() {
        streamRunId = nil
        batchRunId = nil
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeSingleTask?.cancel()
        activeSingleTask = nil
        activeBatchTask?.cancel()
        activeBatchTask = nil
        isRunning = false
        batchProgress = nil
    }

    /// Người dùng bấm **dừng** (1.3.515): huỷ tác vụ và hoàn tất mọi tin đang chạy trong phiên — tin còn rỗng ghi
    /// "Đã dừng." — rồi lưu phiên. Không làm vậy thì luồng bị huỷ thoát mà tin vẫn `isStreaming`, màn AI đồng bộ
    /// ngược trạng thái đó nên dòng "AI đang suy nghĩ" không bao giờ mất.
    public func stopActiveTask() {
        cancelActiveTask()
        guard var session = activeSession else { return }
        var changed = false
        for index in session.messages.indices where session.messages[index].isStreaming {
            session.messages[index].isStreaming = false
            if session.messages[index].content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                session.messages[index].content = "Đã dừng."
            }
            changed = true
        }
        guard changed else { return }
        activeSession = session
        AIChatHistoryStore.shared.saveSession(session, for: session.bookId)
    }

    // MARK: - Mở màn hình toàn màn hình từ bất kỳ đâu

    /// Mở màn hình AI toàn màn hình từ ViewController cao nhất tầng `.normal`.
    public func presentFullScreen(context: ActiveContext? = nil) {
        if let ctx = context {
            self.activeContext = ctx
        }
        guard let ctx = self.activeContext else { return }
        guard !isFullScreenPresented else { return }

        // Chỉ nhờ Reader mở lại bằng `.fullScreenCover` khi Reader đang hiển thị đúng là truyện đang
        // chạy AI. Reader của truyện khác (hoặc Shelf/Discovery) đi đường UIKit `.overFullScreen` bên
        // dưới với `activeContext` của truyện đang chạy — không tháo view hierarchy của Reader đó.
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
                self?.presentFullScreen(context: context)
            }
            return
        }

        let aiView = ReaderAIFullScreenView(
            bookId: ctx.bookId,
            bookTitle: ctx.bookTitle,
            chapterIndex: ctx.chapterIndex,
            chapterTitle: ctx.chapterTitle,
            currentChapterRawContent: ctx.currentChapterRawContent
        )

        let hosting = UIHostingController(rootView: aiView)
        hosting.modalPresentationStyle = .overFullScreen
        self.currentPresentedVC = hosting
        self.isFullScreenPresented = true

        topVC.present(hosting, animated: true, completion: nil)
    }

    /// Đóng màn hình AI toàn màn hình nếu đang mở.
    public func dismissFullScreen(animated: Bool = true) {
        guard isFullScreenPresented, let presentedVC = currentPresentedVC else { return }
        presentedVC.dismiss(animated: animated) { [weak self] in
            self?.isFullScreenPresented = false
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
