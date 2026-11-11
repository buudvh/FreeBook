import Combine
import Foundation
import Observation

/// Nghe hai sự kiện làm bản dịch bằng tiện ích của truyện TTS đang phát đổi giữa chừng, rồi gọi `TTSManager` đọc lại
/// (`TTSManager+ExtensionTranslation`):
///
/// - `TranslationEngineStore.didChangeNotification` (đổi bộ dịch / ngôn ngữ / model / kiểu): chỉ khi **dấu vân tay bộ
///   dịch của truyện đang phát** thật sự đổi so với lúc bắt đầu phát / lần đổi trước — đổi riêng cho truyện khác thì không
///   đụng tới. So vân tay thay vì generation dịch vì generation còn đổi theo từ điển / rule (nhánh đó đã có xử lý riêng).
/// - `TranslationFallbackStatusStore.retryRequest` ("Thử lại").
///
/// Gắn lười ở lượt dựng chương TTS đầu tiên có bật dịch (`processChapterWithEngine`) — TTS chưa dựng chương nào thì
/// không có gì để đọc lại. Không ghi gì vào `TTSManager.swift`.
@MainActor
final class TTSExtensionTranslationObserver {
    static let shared = TTSExtensionTranslationObserver()

    private var engineSubscription: AnyCancellable?
    private var bookSubscription: AnyCancellable?
    private var handledRetryId: UUID?
    /// Vân tay bộ dịch của truyện đang phát, chụp lúc truyện bắt đầu phát và sau mỗi lần đổi.
    private var baseline: (bookId: String, fingerprint: String)?

    private init() {}

    func installIfNeeded() {
        guard engineSubscription == nil else { return }
        let manager = TTSManager.shared
        bookSubscription = manager.$playingBookId
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.captureBaseline() }
            }
        engineSubscription = NotificationCenter.default.publisher(for: TranslationEngineStore.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in self?.handleEngineChange() }
            }
        handledRetryId = TranslationFallbackStatusStore.shared.retryRequest?.id
        observeRetryRequests()
    }

    private func captureBaseline() {
        let manager = TTSManager.shared
        guard !manager.playingBookId.isEmpty else {
            baseline = nil
            return
        }
        baseline = (bookId: manager.playingBookId, fingerprint: manager.translationEngineFingerprint())
    }

    private func handleEngineChange() {
        let manager = TTSManager.shared
        let bookId = manager.playingBookId
        guard !bookId.isEmpty else { return }
        let fingerprint = manager.translationEngineFingerprint()
        let previous = baseline
        baseline = (bookId: bookId, fingerprint: fingerprint)
        guard let previous, previous.bookId == bookId, previous.fingerprint != fingerprint,
              manager.sessionTranslationEnabled else { return }
        manager.rereadCurrentChapterForTranslationChange(onlyChapter: nil, reason: "đổi bộ dịch")
    }

    /// `withObservationTracking` chỉ báo một lần ⇒ gắn lại sau mỗi lần báo; xử lý ở lượt main kế tiếp (lúc báo, giá trị
    /// mới chưa được gán).
    private func observeRetryRequests() {
        withObservationTracking {
            _ = TranslationFallbackStatusStore.shared.retryRequest
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.handlePendingRetry()
                self.observeRetryRequests()
            }
        }
    }

    private func handlePendingRetry() {
        guard let request = TranslationFallbackStatusStore.shared.retryRequest, request.id != handledRetryId else { return }
        handledRetryId = request.id
        TTSManager.shared.refreshExtensionTranslation(bookId: request.bookId, chapterIndex: request.chapterIndex)
    }
}
