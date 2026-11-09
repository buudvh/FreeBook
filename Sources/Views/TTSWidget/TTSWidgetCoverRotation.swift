import Combine
import Foundation

/// Góc xoay **dùng chung** của đĩa bìa widget TTS (1.3.796) — cả kiểu Đĩa nổi lẫn Thanh nghe nhạc. Trước đây
/// `FloatingWidgetContainerViewController` tự giữ `CoverRotationState`; đổi kiểu widget là dựng container mới nên góc
/// phải sống ngoài container (khuôn `AudioCoverRotation` của trình nghe).
///
/// Đồng bộ y như bản cũ trong container: `isPlaying` đổi ⇒ `syncPlaybackState`; đổi sang truyện **khác** (bỏ qua chuỗi rỗng
/// lúc dừng) ⇒ `resetAngle` cho đĩa mới bắt đầu từ góc 0.
@MainActor
final class TTSWidgetCoverRotation {
    static let shared = TTSWidgetCoverRotation()

    let state = CoverRotationState()

    private var lastDistinctBookId = ""
    private var cancellables = Set<AnyCancellable>()

    private init() {
        let manager = TTSManager.shared
        manager.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying in
                self?.state.syncPlaybackState(isPlaying: isPlaying, at: Date())
            }
            .store(in: &cancellables)

        manager.$playingBookId
            .receive(on: RunLoop.main)
            .sink { [weak self] newBookId in
                self?.handleBookChange(newBookId)
            }
            .store(in: &cancellables)
    }

    private func handleBookChange(_ newBookId: String) {
        guard !newBookId.isEmpty else { return }
        guard !lastDistinctBookId.isEmpty else {
            lastDistinctBookId = newBookId
            return
        }
        guard lastDistinctBookId != newBookId else { return }
        lastDistinctBookId = newBookId
        state.resetAngle(isPlaying: TTSManager.shared.isPlaying, at: Date())
    }
}
