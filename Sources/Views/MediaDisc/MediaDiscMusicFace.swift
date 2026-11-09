import SwiftUI

/// Mặt đĩa của trình nghe nhạc (1.3.808), dáng nút đĩa nhạc cũ của Reader: bìa album tròn (44 pt ở đĩa góc, 32 pt ở thanh tab) trên nền tối riêng (nốt
/// nhạc dự phòng trắng mờ vẫn thấy trên nền sáng), **xoay khi đang phát** và đĩa đang hiện (`AudioRotatingCover`, góc chung
/// `AudioCoverRotation`). Album 18+ lúc công tắc NSFW tắt ⇒ không tải / không hiện bìa, chỉ nốt nhạc.
///
/// Chỉ đọc cầu nối `AudioMiniPlayerState` — không chạm `AudioPlaybackSession` (chạm là dựng `AVPlayer`).
struct MediaDiscMusicFace: View {
    /// Đường kính bìa (44 pt ở đĩa góc, 32 pt ở ô giữa thanh tab).
    let size: CGFloat
    /// Đĩa đang hiện trên màn và app không ở nền.
    let isOnScreen: Bool

    @ObservedObject private var mini = AudioMiniPlayerState.shared
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.black.opacity(0.55))
                .frame(width: size, height: size)
            AudioRotatingCover(
                coverUrl: mini.coverUrl,
                referer: nil,
                size: size,
                isRotating: mini.isPlaying && isOnScreen,
                isConcealed: isConcealed
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
    }

    private var isConcealed: Bool { mini.isNsfw && !includeNsfw }

    private var accessibilityTitle: String {
        if isConcealed || mini.trackTitle.isEmpty { return "Trình nghe nhạc" }
        return "Trình nghe nhạc: \(mini.trackTitle)"
    }
}
