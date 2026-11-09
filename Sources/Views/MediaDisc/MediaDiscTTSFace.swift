import SwiftUI

/// Mặt đĩa của TTS (1.3.808, kiểu widget "Đĩa góc dưới"), dáng nút đĩa TTS cũ của Reader: bìa truyện tròn 44 pt trên nền
/// tối, **xoay khi đang đọc** và đĩa đang hiện (`TTSCoverView`, góc chung `TTSWidgetCoverRotation` với kiểu Đĩa nổi và sheet
/// điều khiển nhanh). Bìa nạp qua `TTSCoverImageLoader` của kiểu Đĩa nổi.
///
/// Đọc trạng thái qua projection `TTSWidgetStateReader` — không observe `TTSManager` (vẽ lại theo từng đoạn).
struct MediaDiscTTSFace: View {
    /// Đĩa đang hiện trên màn và app không ở nền.
    let isOnScreen: Bool

    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()

    private static let coverSize: CGFloat = 44

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: Self.coverSize, height: Self.coverSize)
            TTSCoverView(
                image: coverLoader.image,
                size: Self.coverSize,
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
