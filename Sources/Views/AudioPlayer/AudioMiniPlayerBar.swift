import SwiftUI

/// Thanh phát mini của trình nghe âm thanh, nằm **ngay trên `MainTabBar`** ở trang gốc các tab (gắn trong
/// `MainTabBarModifier`, cùng khối `safeAreaInset` ⇒ nội dung trang gốc tự chừa chỗ, không bị che; ẩn cùng thanh tab khi
/// bàn phím hiện). Trang đẩy vào / sheet / cover không có thanh này; hub cũng không có dòng Âm thanh (bỏ ở 1.3.803) —
/// trong Reader dùng nút đĩa (`ReaderAudioDiscButton`), ngoài ra màn khoá.
///
/// Chỉ đọc cầu nối `AudioMiniPlayerState` (không chạm `AudioPlaybackSession` — chạm là dựng `AVPlayer`). Ẩn khi không có
/// album đang mở hoặc màn nghe đang hiện. Album 18+ lúc công tắc NSFW tắt ⇒ tên "Đang phát", không bìa (như màn khoá).
/// Bố cục: đĩa bìa tròn 40pt xoay khi đang phát (`AudioRotatingCover`, cơ chế xoay của widget TTS) · tên bài + nghệ sĩ
/// (+ viên hẹn giờ còn lại `AudioMiniPlayerTimerBadge` khi đang hẹn) · ⏯ · ⏭ · ⏱ (sheet `MediaSleepTimerSheet`, 1.3.807) ·
/// ✕ (dừng hẳn); vạch tiến độ mảnh ở mép trên; chạm phần còn lại ⇒ mở lại màn nghe.
struct AudioMiniPlayerBar: View {
    @ObservedObject private var state = AudioMiniPlayerState.shared
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @State private var showingSleepTimer = false

    /// Rộng mỗi nút điều khiển — 4 nút (⏯ ⏭ ⏱ ✕) như thanh widget TTS (`TTSWidgetBarView.controlWidth`).
    private static let controlWidth: CGFloat = 36

    var body: some View {
        if state.isActive, !state.isScreenPresented {
            bar
                // Dòng báo "Tự sang: <tên>" nằm ngay trên thanh (đáy viên thuốc cách mép trên thanh 6 pt).
                .overlay(alignment: .top) { AudioPlaybackNoticeBanner().alignmentGuide(.top) { $0[.bottom] + 6 } }
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
                    HStack(spacing: 6) {
                        Text(subtitle.isEmpty ? " " : subtitle)
                            .font(.caption)
                            .foregroundStyle(state.isFailed ? AnyShapeStyle(Color.red) : AnyShapeStyle(Color.white.opacity(0.65)))
                            .lineLimit(1)
                        AudioMiniPlayerTimerBadge()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
            .onTapGesture { state.onReopen?() }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Mở màn nghe")

            MiniPlayerControlButton(
                systemImage: state.isPlaying ? "pause.fill" : "play.fill",
                label: state.isPlaying ? "Tạm dừng" : "Phát",
                width: Self.controlWidth,
                showsProgress: state.isLoading && !state.isPlaying
            ) { state.onTogglePlay?() }
            MiniPlayerControlButton(systemImage: "forward.end.fill", label: "Bài sau", width: Self.controlWidth) {
                state.onNext?()
            }
                .disabled(!state.hasNextTrack)
                .opacity(state.hasNextTrack ? 1 : 0.4)
            // ⏱ hẹn giờ tắt nhạc (1.3.807) — cùng sheet với màn nghe / sheet điều khiển của Reader.
            MiniPlayerControlButton(systemImage: "timer", label: "Hẹn giờ tắt", width: Self.controlWidth) {
                showingSleepTimer = true
            }
            MiniPlayerControlButton(systemImage: "xmark", label: "Dừng hẳn trình nghe", width: Self.controlWidth) {
                AppLogger.shared.log("🎵 [AudioPlayerUI] Dừng hẳn từ thanh mini")
                state.onStop?()
            }
        }
        // Dáng chung, giống hệt kiểu "Thanh nghe nhạc" của widget TTS (1.3.796): 56 pt, bo 14, nền đặc tối (1.3.799), vạch tiến độ.
        .miniPlayerBarChrome {
            MiniPlayerProgressLine(fraction: state.progress)
        }
        // Thanh chỉ có khi trình nghe có album (`state.isActive`) ⇒ phiên nghe đã dựng, chạm `shared` không dựng `AVPlayer` mới.
        .sheet(isPresented: $showingSleepTimer) {
            MediaSleepTimerSheet(timer: AudioPlaybackSession.shared.sleepTimer)
        }
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
}
