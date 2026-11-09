import SwiftUI

/// Chỗ giữ **sheet điều khiển nhanh** của đĩa nghe (1.3.812, tách từ `MediaDiscContentView` của 1.3.808): một view 1×1 trong
/// cửa sổ riêng của đĩa (`MediaDiscContainerViewController`), luôn hiện, không nhận chạm. Cả đĩa góc lẫn đĩa ở ô giữa thanh
/// tab đều xin mở qua `MediaDiscWindowManager.presentQuickControls()` (`presentRequestToken`) ⇒ một chỗ giữ sheet duy nhất,
/// sheet luôn ở cửa sổ của đĩa (không đụng màn đang trình bày của cửa sổ chính).
///
/// Sheet theo nguồn: nhạc `AudioQuickControlSheet`, TTS `TTSQuickControlSheet`. Chạm khối đầu sheet (bìa + tên):
/// - Nhạc ⇒ đóng sheet **rồi** mở màn nghe ở trang Đĩa (`AudioPlayerPresenter.reopen(at:)` trong `onDismiss`); Danh sách /
///   Lời cũng vậy, ở trang tương ứng.
/// - TTS ⇒ đóng sheet rồi mở chương đang đọc: Reader của truyện đó đang mở ⇒ chỉ về chương / đoạn đang đọc
///   (`navigateReaderToPlayingChapter`, không đổi tab); chưa mở ⇒ đường "mở chương đang đọc" sẵn có
///   (`openCurrentlyPlayingReader`).
///
/// Nguồn đổi / hết hoặc manager xin đóng (`closeSheetsToken`) ⇒ sheet **đóng** chứ không bị gỡ ngang. Sheet đóng ⇒ báo
/// manager (`quickControlsDidDismiss`) để đĩa đang tạm đứng ở header về chỗ.
struct MediaDiscSheetHost: View {
    @ObservedObject private var manager = MediaDiscWindowManager.shared
    @State private var openSheet: MediaDiscKind?
    /// Chiều cao nội dung từng sheet đo được — giữ qua các lần mở (xem `AudioQuickControlSheet.height`).
    @State private var audioSheetHeight: CGFloat = 0
    @State private var ttsSheetHeight: CGFloat = 0
    /// Việc làm sau khi sheet đóng xong (trình bày từ sheet đang đóng thì UIKit đóng luôn màn mới).
    @State private var pendingAudioPage: AudioPlayerPage?
    @State private var pendingOpensReader = false

    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .sheet(item: $openSheet, onDismiss: sheetDidDismiss) { kind in
                sheetContent(for: kind)
            }
            .onChange(of: manager.presentRequestToken) { _, _ in
                openQuickControls()
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
        guard openSheet == nil, let kind = manager.kind else { return }
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

    private func sheetDidDismiss() {
        manager.quickControlsDidDismiss()
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
