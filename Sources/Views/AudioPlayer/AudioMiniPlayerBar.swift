import SwiftUI

/// Thanh phát mini của trình nghe âm thanh, nằm **ngay trên `MainTabBar`** ở trang gốc các tab (gắn trong
/// `MainTabBarModifier`, cùng khối `safeAreaInset` ⇒ nội dung trang gốc tự chừa chỗ, không bị che; ẩn cùng thanh tab khi
/// bàn phím hiện). Trang đẩy vào / sheet / cover không có thanh này — ở đó dùng dòng Âm thanh của hub.
///
/// Chỉ đọc cầu nối `AudioMiniPlayerState` (không chạm `AudioPlaybackSession` — chạm là dựng `AVPlayer`). Ẩn khi không có
/// album đang mở hoặc màn nghe đang hiện. Album 18+ lúc công tắc NSFW tắt ⇒ tên "Đang phát", không bìa (như hub).
/// Bố cục: đĩa bìa tròn 40pt xoay khi đang phát (`AudioRotatingCover`, cơ chế xoay của widget TTS) · tên bài + nghệ sĩ ·
/// ⏯ · ⏭ · ✕ (dừng hẳn); vạch tiến độ mảnh ở mép trên; chạm phần còn lại ⇒ mở lại màn nghe.
struct AudioMiniPlayerBar: View {
    @ObservedObject private var state = AudioMiniPlayerState.shared
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false

    private static let cornerRadius: CGFloat = 14

    var body: some View {
        if state.isActive, !state.isScreenPresented {
            bar
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var isConcealed: Bool { state.isNsfw && !includeNsfw }

    private var title: String {
        if isConcealed { return "Đang phát" }
        if !state.trackTitle.isEmpty { return state.trackTitle }
        return state.albumTitle.isEmpty ? "Đang tải…" : state.albumTitle
    }

    private var subtitle: String {
        if state.isFailed { return "Lỗi phát — chạm để mở" }
        if isConcealed { return state.isPlaying ? "Chạm để mở lại" : "Đã dừng" }
        return state.artist
    }

    private var bar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 10) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                    Text(subtitle.isEmpty ? " " : subtitle)
                        .font(.caption)
                        .foregroundStyle(state.isFailed ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.white.opacity(0.65)))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.onReopen?() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Mở màn nghe")

            controlButton(
                systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                label: state.isPlaying ? "Tạm dừng" : "Phát",
                showsProgress: state.isLoading && !state.isPlaying
            ) { state.onTogglePlay?() }
            controlButton(systemImage: "forward.end.fill", label: "Bài sau") { state.onNext?() }
                .disabled(!state.hasNextTrack)
                .opacity(state.hasNextTrack ? 1 : 0.4)
            controlButton(systemImage: "xmark", label: "Dừng hẳn trình nghe") {
                AppLogger.shared.log("🎵 [AudioPlayerUI] Dừng hẳn từ thanh mini")
                state.onStop?()
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
        .frame(height: 56)
        .background(FloatingGlassBackground(shape: AnyShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))))
        .overlay(alignment: .top) { progressLine }
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    /// Đĩa tròn 40 pt xoay khi đang phát (cùng góc với trang Đĩa); album 18+ lúc NSFW tắt ⇒ không tải / không hiện bìa.
    private var cover: some View {
        AudioRotatingCover(
            coverUrl: state.coverUrl,
            referer: nil,
            size: 40,
            isRotating: state.isPlaying,
            isConcealed: isConcealed
        )
    }

    private var progressLine: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.tint)
                .frame(width: proxy.size.width * min(1, max(0, state.progress)), height: 2)
        }
        .frame(height: 2)
        .padding(.horizontal, Self.cornerRadius / 2)
        .accessibilityHidden(true)
    }

    private func controlButton(
        systemImage: String,
        label: String,
        showsProgress: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                if showsProgress {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
            }
            .frame(width: 38, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
