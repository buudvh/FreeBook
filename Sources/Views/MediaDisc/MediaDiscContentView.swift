import SwiftUI

/// Nội dung SwiftUI của đĩa nghe góc dưới phải (1.3.808), nằm trong khung 52×52 của `MediaDiscContainerViewController`:
/// nút tròn 52 pt nền kính `FloatingGlassBackground` (theo Cài đặt › Chung › Giao diện, như nút "+" nổi), trong là mặt
/// đĩa của nguồn đang chạy (`MediaDiscMusicFace` / `MediaDiscTTSFace`).
///
/// Chạm ⇒ sheet điều khiển nhanh trình bày từ cửa sổ của đĩa: nhạc `AudioQuickControlSheet`, TTS `TTSQuickControlSheet`.
/// Chạm khối đầu sheet (bìa + tên):
/// - Nhạc ⇒ đóng sheet **rồi** mở màn nghe ở trang Đĩa (`AudioPlayerPresenter.reopen(at:)` trong `onDismiss`); Danh sách /
///   Lời cũng vậy, ở trang tương ứng.
/// - TTS ⇒ đóng sheet rồi mở chương đang đọc: Reader của truyện đó đang mở ⇒ chỉ về chương / đoạn đang đọc
///   (`navigateReaderToPlayingChapter`, không đổi tab); chưa mở ⇒ đường "mở chương đang đọc" sẵn có
///   (`openCurrentlyPlayingReader`).
///
/// `.sheet` gắn ở nút luôn tồn tại; nguồn đổi / hết (nhạc dừng, TTS bắt đầu…) hoặc manager xin đóng ⇒ sheet **đóng** chứ
/// không bị gỡ ngang.
struct MediaDiscContentView: View {
    @ObservedObject private var manager = MediaDiscWindowManager.shared
    @State private var openSheet: MediaDiscKind?
    /// Chiều cao nội dung từng sheet đo được — giữ qua các lần mở (xem `AudioQuickControlSheet.height`).
    @State private var audioSheetHeight: CGFloat = 0
    @State private var ttsSheetHeight: CGFloat = 0
    /// Việc làm sau khi sheet đóng xong (trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới).
    @State private var pendingAudioPage: AudioPlayerPage?
    @State private var pendingOpensReader = false

    var body: some View {
        Button(action: openQuickControls) {
            face
                .frame(width: MediaDiscPlacement.discSize, height: MediaDiscPlacement.discSize)
                .background { FloatingGlassBackground() }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(manager.faceKind == .music ? "Mở điều khiển nhạc" : "Mở điều khiển nhanh của giọng đọc")
        .sheet(item: $openSheet, onDismiss: runPendingAction) { kind in
            sheetContent(for: kind)
        }
        .onChange(of: manager.kind) { _, newKind in
            guard let shown = openSheet, shown != newKind else { return }
            closeSheet()
        }
        .onChange(of: manager.closeSheetsToken) { _, _ in
            guard openSheet != nil else { return }
            closeSheet()
        }
    }

    @ViewBuilder
    private var face: some View {
        switch manager.faceKind {
        case .music:
            MediaDiscMusicFace(isOnScreen: manager.isDiscOnScreen)
        case .tts:
            MediaDiscTTSFace(isOnScreen: manager.isDiscOnScreen)
        }
    }

    @ViewBuilder
    private func sheetContent(for kind: MediaDiscKind) -> some View {
        switch kind {
        case .music:
            AudioQuickControlSheet(
                height: $audioSheetHeight,
                onOpenScreen: { page in
                    pendingAudioPage = page
                    openSheet = nil
                },
                onStop: stopMusic
            )
        case .tts:
            TTSQuickControlSheet(
                height: $ttsSheetHeight,
                onOpenReader: {
                    pendingOpensReader = true
                    openSheet = nil
                },
                onStop: stopReading
            )
        }
    }

    // MARK: - Hành động

    private func openQuickControls() {
        guard let kind = manager.kind else { return }
        AppLogger.shared.log("💿 [MediaDisc] Mở sheet điều khiển nhanh: \(kind.rawValue)")
        pendingAudioPage = nil
        pendingOpensReader = false
        openSheet = kind
    }

    private func closeSheet() {
        pendingAudioPage = nil
        pendingOpensReader = false
        openSheet = nil
    }

    /// "Tắt nhạc": đóng sheet và dừng hẳn trình nghe (đĩa thu lại theo nguồn).
    private func stopMusic() {
        AppLogger.shared.log("💿 [MediaDisc] Tắt nhạc từ sheet điều khiển")
        closeSheet()
        AudioMiniPlayerState.shared.onStop?()
    }

    /// "Tắt đọc": đóng sheet rồi dừng hẳn TTS.
    private func stopReading() {
        AppLogger.shared.log("💿 [MediaDisc] Tắt đọc từ sheet điều khiển")
        closeSheet()
        TTSManager.shared.stop()
    }

    private func runPendingAction() {
        if let page = pendingAudioPage {
            pendingAudioPage = nil
            guard AudioMiniPlayerState.shared.isActive else { return }
            AppLogger.shared.log("💿 [MediaDisc] Mở màn nghe từ sheet điều khiển (trang \(page))")
            AudioPlayerPresenter.reopen(at: page)
        } else if pendingOpensReader {
            pendingOpensReader = false
            openPlayingChapter()
        }
    }

    /// Mở chương TTS đang đọc. Reader của truyện đó đang mở ⇒ chỉ đưa Reader về chương / đoạn đang đọc (cùng thông báo mà
    /// `ShelfView` gửi) — không qua `openCurrentlyPlayingReader` vì kênh đó còn chuyển về tab Kệ Sách.
    private func openPlayingChapter() {
        let tts = TTSManager.shared
        let bookId = tts.playingBookId
        guard !bookId.isEmpty else { return }
        if ReaderView.activeBookId == bookId {
            AppLogger.shared.log("💿 [MediaDisc] Reader đang mở ⇒ về chương đang đọc")
            NotificationCenter.default.post(
                name: NSNotification.Name("navigateReaderToPlayingChapter"),
                object: nil,
                userInfo: [
                    "bookId": bookId,
                    "chapterIndex": tts.playingChapterIndex,
                    "paragraphIndex": tts.currentParentParagraphIndex
                ]
            )
        } else {
            AppLogger.shared.log("💿 [MediaDisc] Mở Reader ở chương đang đọc")
            NotificationCenter.default.post(name: NSNotification.Name("openCurrentlyPlayingReader"), object: nil)
        }
    }
}
