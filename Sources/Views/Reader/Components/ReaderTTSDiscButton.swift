import SwiftUI

/// Nút **đĩa TTS** của Reader (1.3.806), kiểu widget "Thanh nghe nhạc": nằm ngay **trên** nút tai nghe, cùng chỗ và cùng dáng
/// với nút đĩa nhạc (`ReaderAudioDiscButton` — nhạc và TTS không bao giờ cùng phát nên không bao giờ hiện cả hai): nút
/// 52 pt nền kính `FloatingGlassBackground` (theo Cài đặt › Chung › Giao diện), cách nút tai nghe 12 pt.
///
/// Chỉ hiện khi thanh TTS đang **thu gọn** (`TTSWidgetBarPresence.showsReaderDisc`) — trong Reader container ẩn viên nép mép,
/// nút này thay chỗ. Thanh đang bung trong Reader (tắt "Thu gọn khi mở Reader") ⇒ không có nút, thanh nằm sát đáy.
///
/// Trong nút là bìa truyện dạng đĩa **xoay khi đang đọc** (`TTSCoverView`, góc chung `TTSWidgetCoverRotation`). Chạm ⇒
/// sheet điều khiển nhanh `TTSQuickControlSheet` (không bung thanh). TTS dừng hẳn ở nơi khác ⇒ nút biến mất, sheet đóng.
/// View riêng để `ReaderView` không vẽ lại theo trạng thái TTS. `.sheet` gắn ở khung ngoài luôn tồn tại (không trong nhánh
/// `if`), nên nút biến mất là sheet **đóng** chứ không bị gỡ ngang.
struct ReaderTTSDiscButton: View {
    /// Nền đọc tối (`selectedTheme == .dark`) — tông của lớp kính.
    let isDark: Bool
    /// Màu viền kính, trùng màu icon tai nghe.
    let tint: Color

    @ObservedObject private var presence = TTSWidgetBarPresence.shared
    @StateObject private var ttsState = TTSWidgetStateReader()
    @StateObject private var coverLoader = TTSCoverImageLoader()
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingSheet = false
    /// Chiều cao nội dung sheet đo được — giữ qua các lần mở (xem `TTSQuickControlSheet.height`).
    @State private var sheetHeight: CGFloat = 0

    private static let discSize: CGFloat = 44

    var body: some View {
        VStack(spacing: 0) {
            if presence.showsReaderDisc {
                discButton
                    .padding(.trailing, 12)
                    .padding(.bottom, 12)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: presence.showsReaderDisc)
        .sheet(isPresented: $showingSheet) {
            TTSQuickControlSheet(height: $sheetHeight, onStop: stopReading)
        }
        .onChange(of: presence.showsReaderDisc) { _, shows in
            guard !shows else { return }
            showingSheet = false
        }
        .onAppear { refreshCover() }
        .onChange(of: ttsState.snapshot.playingBookId) { _, _ in refreshCover() }
        .onChange(of: ttsState.snapshot.playingCoverUrl) { _, _ in refreshCover() }
    }

    private var discButton: some View {
        Button {
            AppLogger.shared.log("🎧 [TTSWidget] Mở sheet điều khiển TTS từ nút đĩa Reader")
            showingSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .frame(width: Self.discSize, height: Self.discSize)
                TTSCoverView(
                    image: coverLoader.image,
                    size: Self.discSize,
                    rotationState: TTSWidgetCoverRotation.shared.state,
                    isRotating: ttsState.snapshot.isPlaying && scenePhase == .active
                )
            }
            .frame(width: 52, height: 52)
            .background { FloatingGlassBackground(isDark: isDark, outline: tint) }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Điều khiển đọc truyện")
        .accessibilityHint("Mở điều khiển nhanh của giọng đọc")
    }

    /// "Tắt đọc" của sheet: đóng sheet rồi dừng hẳn TTS (nút biến mất theo `showsReaderDisc`).
    private func stopReading() {
        AppLogger.shared.log("🎧 [TTSWidget] Tắt đọc từ sheet điều khiển của Reader")
        showingSheet = false
        TTSManager.shared.stop()
    }

    private func refreshCover() {
        coverLoader.load(
            bookId: ttsState.snapshot.playingBookId,
            coverURL: ttsState.snapshot.playingCoverUrl
        )
    }
}
