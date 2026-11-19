import Combine
import Foundation

/// Mốc **dịch lại khi đang nghe** giữa TTS và Reader (anh Bửu, 2026-11-19: sửa rule / VP / Name lúc truyện đang nghe ⇒ áp
/// bản dịch mới từ **đoạn** — dòng cha `ChapterTextLine.id`, không phải chunk — sau đoạn đang đọc; highlight không lệch).
///
/// - TTS (`TTSManager+Retranslation`) dịch lại chương đang đọc ở nền rồi nối trong **một** nhịp main: dòng ≤
///   `Anchor.boundaryLineId` giữ chữ đang đọc, dòng sau dùng chữ mới; xong công bố `anchor`.
/// - Reader dựng chương mà TTS đang đọc ⇒ áp mốc cùng token: dòng ≤ mốc hiện đúng chữ TTS đọc (`pinnedTexts`), dòng sau
///   dùng bản dựng mới. TTS đang dịch lại đúng chương đó (`pending`) mà chưa có mốc ⇒ Reader chờ tối đa 3 s
///   (`waitForAnchor`); mốc tới muộn hơn ⇒ Reader nắn lại bản đã áp (`ReaderViewModel+TTSRetranslation`).
/// - Mốc **hết hiệu lực** khi TTS dựng lại chữ chương (đọc lại / chuyển chương — `ttsTextRevision` tăng), dừng hẳn, đổi
///   phồn → giản / bộ dịch của phiên ⇒ Reader trả chương đã ghim về bản dựng gốc (không ghim).
/// - Reader đang hoãn dựng lại (panel VP / Name / rule, menu chọn chữ… đang mở) trên đúng chương TTS đọc ⇒ **giữ** lượt nối
///   của TTS (`setReaderHold`) tới khi đóng: trong lúc panel mở Reader còn chữ cũ, TTS đọc chữ mới là lệch highlight.
///
/// Chỉ chạm trên main. Không import SwiftUI (luật `SERVICE_SWIFTUI_IMPORT`).
@MainActor
final class TTSRetranslationCoordinator: ObservableObject {
    struct ChapterRef: Equatable {
        let bookId: String
        let chapterIndex: Int
    }

    /// Mảng chunk `TTSManager.paragraphs` hiện tại thuộc phiên / truyện / chương nào (ghi lúc gán mảng). Lệch phiên / chương
    /// đang phát ⇒ một lượt dựng chương đang chạy, chunk cũ chưa bị thay.
    struct ChunkOwner: Equatable {
        let sessionID: UUID
        let bookId: String
        let chapterIndex: Int
    }

    struct Anchor: Equatable {
        let bookId: String
        let chapterIndex: Int
        /// `TranslateUtils.translationGenerationToken` của bản dịch mới mà TTS vừa nối.
        let token: Int
        /// Cờ phồn → giản + vân tay bộ dịch của phiên lúc nối — phiên đổi một trong hai ⇒ mốc hết hiệu lực.
        let convertsTraditional: Bool
        let engineFingerprint: String
        /// Id dòng cuối cùng (tiêu đề = -1) giữ chữ TTS đang đọc; dòng sau mốc là chữ mới.
        let boundaryLineId: Int
        /// Dòng ≤ mốc mà chữ TTS đọc **khác** bản dịch mới: id ⇒ chữ TTS (đã trim). Dòng ≤ mốc không có ở đây = chữ mới.
        let pinnedTexts: [Int: String]
        /// `TTSManager.chapterContent` ngay sau khi nối — TTS dựng lại chương (đọc lại, sang chương khác) ⇒ mốc hết hiệu lực.
        let contentStamp: String
    }

    enum WaitOutcome {
        /// Không có lượt dịch lại nào của TTS cho chương này (hoặc đã có mốc / Reader đang giữ) — không chờ.
        case notNeeded
        case anchored
        /// TTS bỏ lượt dịch lại (đổi chương, dừng đọc, lỗi tải…) hoặc lượt chờ bị huỷ — không có mốc.
        case cleared
        case timedOut
    }

    static let shared = TTSRetranslationCoordinator()
    static let readerWaitTimeout: TimeInterval = 3

    @Published private(set) var anchor: Anchor?
    /// Tăng mỗi lần `TTSManager.paragraphs` được gán (dựng chương, nối bản dịch, đổi cài đặt) — sheet nghe mini dựng lại
    /// danh sách đầu đoạn + "N/M".
    @Published private(set) var layoutRevision = 0
    /// Tăng mỗi lần `TTSManager.chapterContent` được gán — Reader kiểm lại chương đang ghim chữ theo mốc.
    @Published private(set) var ttsTextRevision = 0
    private(set) var ttsChunkOwner: ChunkOwner?
    /// Lượt dịch lại TTS đang chạy (gộp sự kiện → tải → dịch → chờ Reader → nối). Lượt mới huỷ lượt cũ.
    var retranslationTask: Task<Void, Never>?

    private(set) var pending: ChapterRef?
    private var pendingGeneration: UInt64 = 0
    private weak var holdOwner: AnyObject?
    private var holdChapter: ChapterRef?
    private var waiters: [UUID: (ref: ChapterRef, continuation: CheckedContinuation<Bool, Never>)] = [:]

    private init() {}

    // MARK: - TTS

    /// `didSet` của `TTSManager.paragraphs`.
    func noteTTSParagraphsChanged(owner: ChunkOwner) {
        ttsChunkOwner = owner
        layoutRevision &+= 1
    }

    /// `didSet` của `TTSManager.chapterContent`.
    func noteTTSChapterTextChanged() {
        ttsTextRevision &+= 1
    }

    /// TTS bắt đầu một lượt dịch lại cho `ref`; trả generation để kết thúc đúng lượt.
    func beginPending(_ ref: ChapterRef) -> UInt64 {
        pendingGeneration &+= 1
        pending = ref
        return pendingGeneration
    }

    /// Lượt `generation` xong mà không có mốc (hoặc đã công bố). Lượt mới hơn đang chạy ⇒ không đụng.
    func endPending(generation: UInt64) {
        guard generation == pendingGeneration, let ref = pending else { return }
        pending = nil
        resumeWaiters(for: ref)
    }

    /// TTS vừa nối xong: công bố mốc (kể cả khi không dòng nào giữ chữ cũ).
    func publish(_ newAnchor: Anchor, generation: UInt64) {
        anchor = newAnchor
        endPending(generation: generation)
        resumeWaiters(for: ChapterRef(bookId: newAnchor.bookId, chapterIndex: newAnchor.chapterIndex))
    }

    /// Reader đang hoãn dựng lại trên đúng chương `ref` ⇒ TTS chưa được nối.
    func isHeld(_ ref: ChapterRef) -> Bool {
        holdOwner != nil && holdChapter == ref
    }

    // MARK: - Reader

    /// `ReaderViewModel.setTranslationRefreshDeferred`: bật khi panel / menu chọn chữ mở, tắt khi đóng. Giữ yếu chủ sở hữu ⇒
    /// Reader đóng hẳn mà quên nhả thì lượt nối của TTS tự chạy tiếp.
    func setReaderHold(_ active: Bool, owner: AnyObject, bookId: String, chapterIndex: Int) {
        if active {
            holdOwner = owner
            holdChapter = ChapterRef(bookId: bookId, chapterIndex: chapterIndex)
        } else if holdOwner === owner || holdOwner == nil {
            holdOwner = nil
            holdChapter = nil
        }
    }

    func isPending(bookId: String, chapterIndex: Int) -> Bool {
        pending == ChapterRef(bookId: bookId, chapterIndex: chapterIndex)
    }

    /// Mốc còn hiệu lực cho đúng truyện + chương + bản dựng Reader (token, công tắc dịch, phồn → giản): TTS vẫn đọc chương đó
    /// với cùng cờ phồn → giản + bộ dịch, và chưa dựng lại chữ từ lúc nối.
    func liveAnchor(
        bookId: String,
        chapterIndex: Int,
        token: Int,
        translationEnabled: Bool,
        convertsTraditional: Bool
    ) -> Anchor? {
        guard translationEnabled, let anchor, anchor.bookId == bookId, anchor.chapterIndex == chapterIndex,
              anchor.token == token, anchor.convertsTraditional == convertsTraditional else { return nil }
        let tts = TTSManager.shared
        guard tts.playingBookId == bookId, tts.playingChapterIndex == chapterIndex,
              tts.sessionTranslationEnabled,
              tts.sessionShouldConvertTraditionalToSimplified == anchor.convertsTraditional,
              tts.chapterContent == anchor.contentStamp,
              tts.translationEngineFingerprint() == anchor.engineFingerprint else { return nil }
        return anchor
    }

    /// Reader dựng xong chương mà TTS đang dịch lại ⇒ chờ mốc (tối đa `readerWaitTimeout`). Lượt dựng của Reader bị huỷ
    /// ⇒ thôi chờ ngay (lượt dựng mới `await` lượt cũ trước khi chạy).
    func waitForAnchor(
        bookId: String,
        chapterIndex: Int,
        token: Int,
        translationEnabled: Bool,
        convertsTraditional: Bool
    ) async -> WaitOutcome {
        let ref = ChapterRef(bookId: bookId, chapterIndex: chapterIndex)
        func hasAnchor() -> Bool {
            liveAnchor(bookId: bookId, chapterIndex: chapterIndex, token: token,
                       translationEnabled: translationEnabled, convertsTraditional: convertsTraditional) != nil
        }
        guard !Task.isCancelled, translationEnabled, pending == ref, !isHeld(ref), !hasAnchor() else { return .notNeeded }
        let id = UUID()
        let timedOut = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiters[id] = (ref, continuation)
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(Self.readerWaitTimeout * 1_000_000_000))
                    self?.resumeWaiter(id, timedOut: true)
                }
            }
        } onCancel: {
            // Chạy ở luồng bất kỳ ⇒ về main; người chờ đã đăng ký trước khi main rảnh nên không lọt.
            Task { @MainActor in TTSRetranslationCoordinator.shared.resumeWaiter(id, timedOut: false) }
        }
        if timedOut { return .timedOut }
        return hasAnchor() ? .anchored : .cleared
    }

    // MARK: - Người chờ

    private func resumeWaiters(for ref: ChapterRef) {
        for (id, waiter) in waiters where waiter.ref == ref {
            resumeWaiter(id, timedOut: false)
        }
    }

    private func resumeWaiter(_ id: UUID, timedOut: Bool) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: timedOut)
    }
}
