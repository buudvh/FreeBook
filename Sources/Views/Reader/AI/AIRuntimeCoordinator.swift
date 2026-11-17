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
    /// truyện B đang mở vẫn phải có toast cho A. Nhận đúng `bookId` ⇒ kết quả chưa xem của truyện đó coi như đã xem
    /// (`+UnseenResults`, 1.3.630) — bắt mọi đường mở màn AI: nút nổi, nút AI trong Reader.
    @Published public var presentedAIBookId: String? = nil {
        didSet {
            if let bookId = presentedAIBookId, bookId != oldValue {
                markResultSeen(bookId: bookId)
            }
        }
    }
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
    /// Khoá name người dùng đã bấm ✕ xoá, **theo tin** — mọi đường dựng lại nội dung tin kết quả từ danh sách tên
    /// đều lọc qua đây (`AIRuntimeCoordinator+NameRemoval`). Giữ trong bộ nhớ suốt phiên app.
    var removedNameKeys: [UUID: Set<String>] = [:]
    /// Các lần sửa name bằng nút bút chì, **theo tin**, đúng thứ tự — áp lại sau `removedNameKeys` ở mọi đường dựng lại
    /// nội dung tin (`AIRuntimeCoordinator+NameEdits`). Giữ trong bộ nhớ suốt phiên app.
    var nameEdits: [UUID: [AINameEdit]] = [:]
    /// Ngữ cảnh mở màn AI theo truyện — nút nổi mở đúng màn AI của truyện được chạm. Chỉ giữ truyện còn entry trong
    /// `runs` và truyện mở AI gần nhất (`pruneContexts`), vì ngữ cảnh mang cả nội dung chương. `internal` cho
    /// `+UnseenResults` (dựng lại ngữ cảnh của kết quả chưa xem lúc mở app).
    var contexts: [String: ActiveContext] = [:]
    private var latestContextBookId: String? = nil
    private var cancellables = Set<AnyCancellable>()
    private weak var currentPresentedVC: UIViewController? = nil

    static let chatTaskTitle = "AI đang suy nghĩ"

    private init() {
        setupTTSObservers()
        restoreUnseenResults()
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

    /// Màn AI của một truyện vừa hiện (mọi lối mở — `ReaderAIFullScreenView+Context`, 1.3.969): ghi ngữ cảnh của chính
    /// màn đó như truyện mở AI gần nhất, rồi đặt `presentedAIBookId`.
    func screenDidAppear(_ context: ActiveContext) {
        updateContext(context)
        presentedAIBookId = context.bookId
    }

    /// Bỏ ngữ cảnh của truyện đã rảnh, trừ truyện mở AI gần nhất và truyện đang mở màn AI.
    func pruneContexts() {
        contexts = contexts.filter {
            runs[$0.key] != nil || $0.key == latestContextBookId || $0.key == presentedAIBookId
        }
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
            // Bộ xoay tài khoản Google của **lượt này** (1.3.616) — bị giới hạn thì tráo tài khoản rồi gửi lại.
            let rotation = GoogleAccountRotation(config: config)
            do {
                var accumulated = ""
                attempts: while true {
                    guard let stream = await self?.makeChatStream(config: config, messages: messages, session: session) else { return }
                    accumulated = ""
                    var lastUIUpdateTime: TimeInterval = 0
                    do {
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
                    } catch {
                        guard !Task.isCancelled else { return }
                        // Chỉ tráo khi lượt chưa phát chữ nào — đang có chữ mà tráo thì câu trả lời đứt rồi viết lại.
                        guard accumulated.isEmpty,
                              let coordinator = self,
                              await coordinator.rotateGoogleAccount(after: error, rotation: rotation, session: session) else {
                            throw error
                        }
                        continue attempts
                    }
                    break
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
                    self.finishRun(bookId: bookId, outcome: .finished)
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
                    self.finishRun(bookId: bookId, outcome: .failed)
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
    ///
    /// **Không bao giờ im lặng bỏ qua** (1.3.969, anh Bửu: chạy từ 2 truyện AI trở lên, chạm truyện chạy trước ở hub thì
    /// không mở được). Trước đó ba lối ra không làm gì mà không ghi log: cờ `presentedAIBookId` còn đó, không tìm được màn
    /// trên cùng, và nhờ Reader mở lại (`reopenReaderAI`) mà Reader không mở — `activeReaderBookId` còn trỏ truyện của
    /// Reader đã rời đi (Reader rời màn lúc cờ cover còn bật thì không xoá nó), Reader đang bị màn khác che, hoặc cờ cover
    /// của Reader đã bật sẵn nên gán lại không có tác dụng. Nay: nhờ Reader xong 0,8 s mà màn AI chưa lên ⇒ mở bằng UIKit;
    /// cờ `presentedAIBookId` của màn UIKit đã bị gỡ ⇒ dọn rồi mở; mọi lối từ chối ghi `❌`.
    public func presentFullScreen(bookId: String) {
        guard let ctx = contexts[bookId] ?? minimalContext(bookId: bookId) else {
            AppLogger.shared.log("❌ 🤖 [AI] Không có ngữ cảnh để mở màn AI của truyện \(bookId)")
            return
        }
        if let presented = presentedAIBookId {
            // Màn AI mở bằng UIKit đã bị gỡ khỏi cây mà không chạy `onDisappear` ⇒ cờ kẹt: dọn rồi mở tiếp.
            if let vc = currentPresentedVC, vc.presentingViewController == nil {
                AppLogger.shared.log("❌ 🤖 [AI] Cờ màn AI đang mở bị kẹt (màn đã đóng) — dọn rồi mở truyện \(bookId)")
                currentPresentedVC = nil
                presentedAIBookId = nil
            } else {
                AppLogger.shared.log("❌ 🤖 [AI] Đang mở màn AI của truyện \(presented) — bỏ qua yêu cầu mở truyện \(bookId)")
                return
            }
        }

        // Chỉ nhờ Reader mở lại bằng `.fullScreenCover` khi Reader đang hiển thị đúng là truyện đang
        // chạy AI. Reader của truyện khác (hoặc Shelf/Discovery) đi đường UIKit `.overFullScreen` bên
        // dưới với ngữ cảnh của truyện đang chạy — không tháo view hierarchy của Reader đó.
        if activeReaderBookId == ctx.bookId {
            AppLogger.shared.log("🤖 [AI] Nhờ Reader đang mở mở lại màn AI của truyện \(bookId)")
            NotificationCenter.default.post(
                name: NSNotification.Name("reopenReaderAI"),
                object: nil,
                userInfo: ["bookId": ctx.bookId]
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
                guard let self, self.presentedAIBookId == nil else { return }
                AppLogger.shared.log("❌ 🤖 [AI] Reader không mở lại được màn AI của truyện \(bookId) — mở bằng UIKit")
                self.presentOverTop(ctx)
            }
            return
        }
        presentOverTop(ctx)
    }

    /// Lưới an toàn (1.3.969): truyện còn lượt / kết quả trong `runs` mà mất ngữ cảnh ⇒ mở màn AI với ngữ cảnh tối thiểu
    /// (tên truyện, chương đầu, không nội dung chương) — xem được tiến độ / kết quả quét còn hơn không mở được.
    private func minimalContext(bookId: String) -> ActiveContext? {
        guard let state = runs[bookId] else { return nil }
        AppLogger.shared.log("❌ 🤖 [AI] Mất ngữ cảnh của truyện \(bookId) dù còn lượt AI — mở màn AI với ngữ cảnh tối thiểu")
        let context = ActiveContext(
            bookId: bookId, bookTitle: state.bookTitle, chapterIndex: 0, chapterTitle: "", currentChapterRawContent: ""
        )
        contexts[bookId] = context
        return context
    }

    /// Trình bày màn AI của `ctx` bằng UIKit `.overFullScreen` từ màn trên cùng của cửa sổ chính; màn đó đang mở / đóng dở
    /// ⇒ thử lại mỗi 0,3 s, tối đa 10 lần.
    private func presentOverTop(_ ctx: ActiveContext, attempt: Int = 0) {
        guard presentedAIBookId == nil else { return }
        guard let topVC = findTopViewController() else {
            AppLogger.shared.log("❌ 🤖 [AI] Không tìm thấy màn trên cùng để mở màn AI của truyện \(ctx.bookId)")
            return
        }
        if topVC.isBeingPresented || topVC.isBeingDismissed {
            guard attempt < 10 else {
                AppLogger.shared.log("❌ 🤖 [AI] Màn trên cùng mở / đóng dở quá lâu — không mở được màn AI của truyện \(ctx.bookId)")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentOverTop(ctx, attempt: attempt + 1)
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

        // Trình bày bằng UIKit ⇒ không thừa hưởng `.tint` của `MainTabView`, gắn lại màu nhấn.
        let hosting = UIHostingController(rootView: aiView.appAccentTint())
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
        // Scene giao diện chính (`AppMainWindowScene`) trước: scene của PiP cũng có thể đang `foregroundActive`.
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = AppMainWindowScene.current()
                ?? scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }

        // Bỏ cửa sổ lớp phủ và cửa sổ đang ẩn (khuôn `MediaDiscPlacement.mainWindow`).
        let candidates = windowScene.windows.filter {
            !($0 is AppOverlayWindow) && $0.windowLevel == .normal && !$0.isHidden
        }
        guard let window = candidates.first(where: \.isKeyWindow) ?? candidates.first,
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
