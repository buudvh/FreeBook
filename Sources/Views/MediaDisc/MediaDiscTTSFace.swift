import SwiftUI

/// Mặt đĩa của TTS (1.3.808; kiểu widget TTS duy nhất từ 1.3.859), dáng nút đĩa TTS cũ của Reader: bìa truyện tròn (32 pt trong nửa viên) trên nền
/// tối, **xoay khi đang đọc** và đĩa đang hiện (`TTSCoverView`, góc chung `TTSWidgetCoverRotation` với sheet điều khiển
/// nhanh). Bìa nạp qua `TTSCoverImageLoader`.
///
/// Đọc trạng thái qua projection `TTSWidgetStateReader` — không observe `TTSManager` (vẽ lại theo từng đoạn).
struct MediaDiscTTSFace: View {
    /// Đường kính bìa (32 pt trong nửa viên).
    let size: CGFloat
    /// Đĩa đang hiện trên màn và app không ở nền.
    let isOnScreen: Bool

    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: size, height: size)
            TTSCoverView(
                image: coverLoader.image,
                size: size,
                rotationState: TTSWidgetCoverRotation.shared.state,
                isRotating: ttsState.snapshot.isPlaying && isOnScreen
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Điều khiển đọc truyện")
        .onAppear { refreshCover() }
        .onChange(of: ttsState.snapshot.playingBookId) { _, _ in refreshCover() }
        .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in refreshCover() }
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }
}
