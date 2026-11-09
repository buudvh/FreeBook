import SwiftUI

/// Nút **đĩa nhạc** của Reader, nằm ngay **trên** nút tai nghe (`ReaderView.readerTTSControl`): cùng cỡ 52 pt, cùng nền kính
/// `FloatingGlassBackground` (theo Cài đặt › Chung › Giao diện), cách nút tai nghe 12 pt. Chỉ hiện khi có album đang mở
/// trong trình nghe (`AudioMiniPlayerState.isActive`) — không có album thì không chiếm chỗ, nút tai nghe đứng nguyên chỗ cũ.
///
/// Trong nút là bìa album dạng đĩa tròn **xoay khi đang phát**, đứng yên khi dừng — `AudioRotatingCover` với góc dùng chung
/// `AudioCoverRotation` (cùng góc với thanh mini, trang Đĩa và sheet). Album 18+ lúc công tắc NSFW tắt ⇒ không tải / không
/// hiện bìa, chỉ nốt nhạc (như thanh mini). Đĩa nằm trên nền tối riêng để nốt nhạc dự phòng (trắng mờ) vẫn thấy ở nền đọc
/// sáng.
///
/// Chạm ⇒ sheet điều khiển nhanh `AudioQuickControlSheet`. Mở màn nghe (⤢ / Danh sách / Lời) chờ sheet đóng xong
/// (`onDismiss`) rồi mới trình bày (`AudioPlayerPresenter.reopen(at:)`): trình bày từ sheet đang đóng thì UIKit đóng luôn
/// màn mới. Album bị dừng ở nơi khác (TTS bắt đầu đọc — nhạc và TTS không bao giờ cùng phát) ⇒ nút biến mất, sheet đóng.
///
/// Chỉ đọc cầu nối `AudioMiniPlayerState` (không chạm `AudioPlaybackSession` khi trình nghe chưa mở — chạm là dựng
/// `AVPlayer`); là view riêng để `ReaderView` không bị vẽ lại theo tiến độ bài. `.sheet` gắn ở khung ngoài luôn tồn tại
/// (không gắn trong nhánh `if`), nên tắt nhạc là sheet **đóng** chứ không bị gỡ ngang.
struct ReaderAudioDiscButton: View {
    /// Nền đọc tối (`selectedTheme == .dark`) — tông của lớp kính.
    let isDark: Bool
    /// Màu viền kính, trùng màu icon tai nghe.
    let tint: Color

    @ObservedObject private var mini = AudioMiniPlayerState.shared
    @AppStorage(RepositoryFilterPolicy.includeNsfwDefaultsKey) private var includeNsfw = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSheet = false
    /// Chiều cao nội dung sheet đo được — giữ qua các lần mở (xem `AudioQuickControlSheet.height`).
    @State private var sheetHeight: CGFloat = 0
    /// Trang màn nghe cần mở sau khi sheet đóng xong.
    @State private var pendingPage: AudioPlayerPage? = nil

    private static let discSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            if mini.isActive {
                discButton
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: mini.isActive)
        .sheet(isPresented: $showingSheet, onDismiss: openPendingScreen) {
            AudioQuickControlSheet(
                height: $sheetHeight,
                onOpenScreen: { page in
                    pendingPage = page
                    showingSheet = false
                },
                onStop: stopMusic
            )
        }
        .onChange(of: mini.isActive) { _, isActive in
            guard !isActive else { return }
            pendingPage = nil
            showingSheet = false
        }
    }

    private var isConcealed: Bool { mini.isNsfw && !includeNsfw }

    private var discButton: some View {
        Button {
            AppLogger.shared.log("🎵 [AudioPlayerUI] Mở sheet điều khiển nhạc từ nút đĩa Reader")
            showingSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: Self.discSize, height: Self.discSize)
                AudioRotatingCover(
                    coverUrl: mini.coverUrl,
                    referer: nil,
                    size: Self.discSize,
                    isRotating: mini.isPlaying && scenePhase == .active,
                    isConcealed: isConcealed
                )
            }
            .frame(width: 52, height: 52)
            .background { FloatingGlassBackground(isDark: isDark, outline: tint) }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityHint("Mở điều khiển nhạc")
    }

    private var accessibilityTitle: String {
        if isConcealed || mini.trackTitle.isEmpty { return "Trình nghe nhạc" }
        return "Trình nghe nhạc: \(mini.trackTitle)"
    }

    /// "Tắt nhạc" của sheet: đóng sheet và dừng hẳn trình nghe (nút đĩa biến mất theo `isActive`).
    private func stopMusic() {
        AppLogger.shared.log("🎵 [AudioPlayerUI] Tắt nhạc từ sheet điều khiển của Reader")
        pendingPage = nil
        showingSheet = false
        AudioMiniPlayerState.shared.onStop?()
    }

    private func openPendingScreen() {
        guard let page = pendingPage else { return }
        pendingPage = nil
        guard mini.isActive else { return }
        AppLogger.shared.log("🎵 [AudioPlayerUI] Mở màn nghe từ sheet điều khiển của Reader (trang \(page))")
        AudioPlayerPresenter.reopen(at: page)
    }
}
