import Combine
import Foundation

/// Báo cho người dùng khi TTS phải đọc bản QT (hoặc chữ gốc) vì tiện ích dịch lỗi ở một chương — **đúng lúc TTS bắt
/// đầu đọc chương đó**, không phải lúc dịch xong (lượt nạp trước chương kế có thể bị bỏ rồi dựng lại).
///
/// - `recordProcessed` (gọi sau mỗi lượt TTS dựng chương bằng tiện ích) ghi báo **chờ** theo chương; `nil` = chương dịch
///   đủ / dùng bản của Reader ⇒ xoá báo chờ và cho phép báo lại lần lỗi sau.
/// - Báo chờ chỉ thành toast khi `TTSManager` phát tới đúng chương đó (`playingBookId` + `playingChapterIndex`, hoặc
///   ngay lúc ghi nếu đang phát chương đó), một lần mỗi chương.
/// - Reader đã ghi báo cho chương (`TranslationFallbackStatusStore`, dải báo đầu chương) ⇒ không toast.
/// - Toast đi qua `TTSPresentationEventCenter` (Services không gọi `ToastManager`).
@MainActor
final class TTSTranslationFallbackNotifier {
    static let shared = TTSTranslationFallbackNotifier()

    private static let maxPending = 16
    private static let maxNotified = 64

    private var pending: [String: TranslationFallbackStatus] = [:]
    private var pendingOrder: [String] = []
    /// Chương đã toast, cũ nhất ở đầu.
    private var notified: [String] = []
    private var playingSubscription: AnyCancellable?

    private init() {}

    func recordProcessed(_ status: TranslationFallbackStatus?, bookId: String, chapterIndex: Int) {
        observePlayingChapterIfNeeded()
        let key = Self.key(bookId: bookId, chapterIndex: chapterIndex)
        pendingOrder.removeAll { $0 == key }
        guard let status else {
            pending[key] = nil
            notified.removeAll { $0 == key }
            return
        }
        pending[key] = status
        pendingOrder.append(key)
        while pendingOrder.count > Self.maxPending {
            pending[pendingOrder.removeFirst()] = nil
        }
        let manager = TTSManager.shared
        if manager.playingBookId == bookId, manager.playingChapterIndex == chapterIndex {
            flush(bookId: bookId, chapterIndex: chapterIndex)
        }
    }

    private func observePlayingChapterIfNeeded() {
        guard playingSubscription == nil else { return }
        let manager = TTSManager.shared
        playingSubscription = manager.$playingChapterIndex
            .combineLatest(manager.$playingBookId)
            .sink { [weak self] chapterIndex, bookId in
                Task { @MainActor [weak self] in self?.flush(bookId: bookId, chapterIndex: chapterIndex) }
            }
    }

    private func flush(bookId: String, chapterIndex: Int) {
        guard !bookId.isEmpty, chapterIndex >= 0 else { return }
        let key = Self.key(bookId: bookId, chapterIndex: chapterIndex)
        guard let status = pending.removeValue(forKey: key) else { return }
        pendingOrder.removeAll { $0 == key }
        guard TranslationFallbackStatusStore.shared.status(bookId: bookId, chapterIndex: chapterIndex) == nil,
              !notified.contains(key) else { return }
        notified.append(key)
        if notified.count > Self.maxNotified {
            notified.removeFirst(notified.count - Self.maxNotified)
        }
        let replacement = status.keptOriginalLineCount >= status.failedLineCount ? "chữ gốc" : "bản QT"
        AppLogger.shared.log("❌ [ExtTranslate] TTS chương \(chapterIndex + 1): \(status.detailText) ⇒ đọc \(replacement)")
        TTSPresentationEventCenter.shared.send(.showToast(
            message: "\(status.engineName) lỗi, TTS đọc \(replacement) thay thế",
            type: .error
        ))
    }

    private static func key(bookId: String, chapterIndex: Int) -> String {
        "\(bookId)#\(chapterIndex)"
    }
}
