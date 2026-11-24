import Combine
import Foundation

/// Mục lục của sheet Hẹn giờ TTS (`TTSQuickTimerSheet` giữ, `TTSQuickTimerChapterList` vẽ — mở từ nút "Mục lục" / ⏱ của
/// sheet nghe mini): chỉ phát **danh sách chương của phiên** và **chỉ số chương đang phát**.
///
/// Trước đây sheet lẫn danh sách `@ObservedObject` thẳng `TTSManager` ⇒ mỗi câu (chỉ số đoạn, highlight), mỗi giây hẹn giờ,
/// mỗi lần đệm tiếng / nhiệt độ đổi… đều dựng lại cả danh sách vài nghìn chương — cuộn mục lục giật theo nhịp đọc.
///
/// Tên chương không nằm ở đây: hàng vẫn tra `TTSManager.displayTitle(for:)` (cặp với ô tìm của danh sách), danh sách đọc
/// `TranslationDisplayRevision` để vẽ lại khi từ điển / rule / cấu hình dịch đổi.
@MainActor
final class TTSChapterListReader: ObservableObject {
    @Published private(set) var chapters: [TTSChapterInfo]
    @Published private(set) var playingChapterIndex: Int

    private var cancellables = Set<AnyCancellable>()

    init(manager: TTSManager? = nil) {
        let manager = manager ?? TTSManager.shared
        chapters = manager.chaptersQueue
        playingChapterIndex = manager.playingChapterIndex

        // `$x` phát giá trị **mới** (willSet) ⇒ dùng thẳng giá trị nhận được, không đọc lại manager.
        manager.$chaptersQueue
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] queue in
                guard let self, queue != self.chapters else { return }
                self.chapters = queue
            }
            .store(in: &cancellables)
        manager.$playingChapterIndex
            .dropFirst()
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] index in
                guard let self, index != self.playingChapterIndex else { return }
                self.playingChapterIndex = index
            }
            .store(in: &cancellables)
    }
}
