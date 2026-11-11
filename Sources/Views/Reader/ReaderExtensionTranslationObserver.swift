import Combine
import Foundation
import Observation

/// Nối `ReaderViewModel` với bộ dịch tiện ích: nghe đổi bộ dịch và "Thử lại" của `TranslationFallbackStatusStore`
/// (TTS nghe riêng ở `TTSExtensionTranslationObserver`). Mỗi `ReaderViewModel` giữ một bản, gắn một lần ở
/// `setupSubscriptions`.
@MainActor
final class ReaderExtensionTranslationObserver {
    private weak var viewModel: ReaderViewModel?
    private var engineSubscription: AnyCancellable?
    /// Yêu cầu "Thử lại" đã xử lý — chống xử lý lặp, và bỏ yêu cầu cũ còn sót từ Reader trước lúc gắn.
    private var handledRetryId: UUID?

    func attach(to viewModel: ReaderViewModel) {
        guard self.viewModel == nil else { return }
        self.viewModel = viewModel
        engineSubscription = NotificationCenter.default.publisher(for: TranslationEngineStore.didChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.viewModel?.handleTranslationEngineChange()
                }
            }
        handledRetryId = TranslationFallbackStatusStore.shared.retryRequest?.id
        observeRetryRequests()
    }

    /// `withObservationTracking` chỉ báo một lần ⇒ gắn lại sau mỗi lần báo; xử lý ở lượt main kế tiếp (lúc báo,
    /// giá trị mới chưa được gán).
    private func observeRetryRequests() {
        withObservationTracking {
            _ = TranslationFallbackStatusStore.shared.retryRequest
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.viewModel != nil else { return }
                self.handlePendingRetry()
                self.observeRetryRequests()
            }
        }
    }

    private func handlePendingRetry() {
        guard let request = TranslationFallbackStatusStore.shared.retryRequest, request.id != handledRetryId else { return }
        handledRetryId = request.id
        viewModel?.handleTranslationRetry(request)
    }
}
