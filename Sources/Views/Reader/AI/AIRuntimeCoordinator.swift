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

    @Published public private(set) var isRunning: Bool = false
    @Published public private(set) var activeTaskTitle: String = "AI đang suy nghĩ"
    @Published public var isFullScreenPresented: Bool = false
    @Published public private(set) var activeContext: ActiveContext? = nil
    @Published public var activeSessionId: UUID? = nil
    @Published public var activeSession: AIChatSession? = nil
    @Published public var batchProgress: (current: Int, total: Int)? = nil
    @Published public var batchExtractedNames: [AIExtractedName] = []
    public var isReaderActive: Bool = false

    private var activeStreamingTask: Task<Void, Never>? = nil
    private var activeBatchTask: Task<Void, Never>? = nil
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

        activeStreamingTask = Task { [weak self] in
            do {
                let stream: AsyncThrowingStream<String, Error>
                if config.activeProfile.apiFormat == "anthropic" {
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
                        await MainActor.run {
                            guard let self = self else { return }
                            if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                                self.activeSession?.messages[idx].content = accumulated
                            }
                        }
                        onDelta(accumulated)
                    }
                }

                guard !Task.isCancelled else { return }

                // Tự động kiểm tra và bóc tách nếu phản hồi chứa mảng JSON tên riêng
                let extracted = AINameExtractionBatchProcessor.shared.parseNamesFromJSONString(accumulated)
                let decorated = extracted.isEmpty ? nil : AIBookDataInspector.shared.decorateExtractedNames(names: extracted, bookId: bookId)

                onComplete(accumulated)

                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeStreamingTask = nil
                    if let idx = self.activeSession?.messages.firstIndex(where: { $0.id == assistantMsgId }) {
                        if let dec = decorated, !dec.isEmpty {
                            self.activeSession?.messages[idx].content = "Đã tìm thấy \(dec.count) tên riêng trong phản hồi:"
                            self.activeSession?.messages[idx].extractedNames = dec
                        } else {
                            self.activeSession?.messages[idx].content = accumulated
                        }
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "AI đã hoàn tất phản hồi!", type: .success)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
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

    /// Bắt đầu lọc tên riêng chương hiện tại.
    public func startExtractNamesCurrentChapter(
        bookId: String,
        rawContent: String,
        config: AIConfiguration,
        session: AIChatSession? = nil,
        assistantMsgId: UUID? = nil,
        onComplete: @escaping ([AIExtractedName]) -> Void,
        onError: @escaping (String) -> Void
    ) {
        cancelActiveTask()
        isRunning = true
        activeTaskTitle = "AI đang suy nghĩ"
        if let s = session {
            self.activeSession = s
            self.activeSessionId = s.id
        }

        activeSingleTask = Task { [weak self] in
            do {
                let rawNames = try await AINameExtractionBatchProcessor.shared.extractNamesFromText(text: rawContent, config: config)
                guard !Task.isCancelled else { return }
                let names = AIBookDataInspector.shared.decorateExtractedNames(names: rawNames, bookId: bookId)
                onComplete(names)

                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeSingleTask = nil
                    if let mid = assistantMsgId, let idx = self.activeSession?.messages.firstIndex(where: { $0.id == mid }) {
                        self.activeSession?.messages[idx].content = "Đã tìm thấy \(names.count) tên riêng trong chương này:"
                        self.activeSession?.messages[idx].extractedNames = names
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "Đã tìm thấy \(names.count) tên riêng!", type: .success)
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                onError(error.localizedDescription)
                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeSingleTask = nil
                    if let mid = assistantMsgId, let idx = self.activeSession?.messages.firstIndex(where: { $0.id == mid }) {
                        self.activeSession?.messages[idx].content = "Lỗi lọc tên riêng: \(error.localizedDescription)"
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "Lọc tên riêng thất bại.", type: .error)
                    }
                }
            }
        }
    }

    /// Bắt đầu quét tên riêng toàn bộ chương đã tải (batch).
    public func startBatchExtraction(
        bookId: String,
        config: AIConfiguration,
        session: AIChatSession? = nil,
        assistantMsgId: UUID? = nil,
        onProgress: @escaping (Int, Int, [AIExtractedName]) -> Void,
        onComplete: @escaping ([AIExtractedName]) -> Void
    ) {
        cancelActiveTask()
        isRunning = true
        activeTaskTitle = "Đang quét tên riêng..."
        batchProgress = (0, 1)
        batchExtractedNames.removeAll()
        if let s = session {
            self.activeSession = s
            self.activeSessionId = s.id
        }

        activeBatchTask = Task { [weak self] in
            do {
                let results = try await AINameExtractionBatchProcessor.shared.extractNamesFromDownloadedChapters(
                    bookId: bookId,
                    config: config
                ) { current, total, partial in
                    let decorated = AIBookDataInspector.shared.decorateExtractedNames(names: partial, bookId: bookId)
                    Task { @MainActor [weak self] in
                        guard let self = self, !Task.isCancelled else { return }
                        self.batchProgress = (current, total)
                        self.batchExtractedNames = decorated
                        self.activeTaskTitle = "Đang quét: Batch \(current)/\(total)"
                        onProgress(current, total, decorated)
                    }
                }
                guard !Task.isCancelled else { return }
                let finalResults = AIBookDataInspector.shared.decorateExtractedNames(names: results, bookId: bookId)

                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeBatchTask = nil
                    self.batchExtractedNames = finalResults
                    if let mid = assistantMsgId, let idx = self.activeSession?.messages.firstIndex(where: { $0.id == mid }) {
                        self.activeSession?.messages[idx].content = "Đã quét xong \(finalResults.count) tên riêng từ các chương đã tải:"
                        self.activeSession?.messages[idx].extractedNames = finalResults
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    onComplete(finalResults)
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "Đã quét xong \(finalResults.count) tên riêng!", type: .success)
                    }
                }
            } catch {
                await MainActor.run {
                    guard let self = self else { return }
                    self.isRunning = false
                    self.activeBatchTask = nil
                    if let mid = assistantMsgId, let idx = self.activeSession?.messages.firstIndex(where: { $0.id == mid }) {
                        self.activeSession?.messages[idx].content = "Lỗi quét tên riêng: \(error.localizedDescription)"
                        self.activeSession?.messages[idx].isStreaming = false
                    }
                    if let s = self.activeSession { AIChatHistoryStore.shared.saveSession(s, for: bookId) }
                    if !self.isFullScreenPresented {
                        ToastManager.shared.show(message: "Quét tên riêng bị gián đoạn.", type: .error)
                    }
                }
            }
        }
    }

    /// Huỷ tác vụ AI đang thực thi.
    public func cancelActiveTask() {
        activeStreamingTask?.cancel()
        activeStreamingTask = nil
        activeSingleTask?.cancel()
        activeSingleTask = nil
        activeBatchTask?.cancel()
        activeBatchTask = nil
        isRunning = false
        batchProgress = nil
    }

    // MARK: - Mở màn hình toàn màn hình từ bất kỳ đâu

    /// Mở màn hình AI toàn màn hình từ ViewController cao nhất tầng `.normal`.
    public func presentFullScreen(context: ActiveContext? = nil) {
        if let ctx = context {
            self.activeContext = ctx
        }
        guard let ctx = self.activeContext else { return }
        guard !isFullScreenPresented else { return }

        if isReaderActive {
            NotificationCenter.default.post(name: NSNotification.Name("reopenReaderAI"), object: nil)
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
