import Combine
import Foundation

/// Góc xoay **dùng chung** của bìa đĩa trình nghe (thanh phát mini ở mọi tab + trang Đĩa của màn nghe): một
/// `CoverRotationState` của widget TTS (cùng cơ chế, không nhân bản) sống suốt tiến trình, nên đổi tab / mở màn nghe / thu
/// nhỏ đều giữ đúng góc, dừng thì đứng yên ở góc đang có.
///
/// Trạng thái phát lấy từ cầu nối `AudioMiniPlayerState` (không chạm `AudioPlaybackSession` ⇒ không dựng `AVPlayer`):
/// `isPlaying` đổi ⇒ `syncPlaybackState`; đổi album (`bookId`) ⇒ `resetAngle` (đĩa mới bắt đầu từ góc 0). View chỉ quyết
/// định có gắn animation hay không (`TTSRotatingCoverView.isRotating` = đang phát **và** đang hiện).
@MainActor
final class AudioCoverRotation {
    static let shared = AudioCoverRotation()

    let state = CoverRotationState()

    private var cancellables = Set<AnyCancellable>()

    private init() {
        let mini = AudioMiniPlayerState.shared
        state.syncPlaybackState(isPlaying: mini.isPlaying)
        // `@Published` phát ở willSet ⇒ dùng giá trị được phát ra, không đọc lại `mini.isPlaying`.
        mini.$isPlaying
            .removeDuplicates()
            .sink { [weak self] isPlaying in
                self?.state.syncPlaybackState(isPlaying: isPlaying)
            }
            .store(in: &cancellables)
        mini.$bookId
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                // Lúc này chỉ `bookId` đang đổi ⇒ `isPlaying` đọc được là giá trị hiện hành.
                self?.state.resetAngle(isPlaying: AudioMiniPlayerState.shared.isPlaying)
            }
            .store(in: &cancellables)
    }
}
