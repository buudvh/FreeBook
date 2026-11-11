import SwiftUI

/// Vỏ của sheet "đang đọc chương này" (`ReaderTTSSameChapterSheet`) khi trình bày qua `OverlaySheetPresenter` — sheet nằm
/// **trên** mọi viên thuốc (đĩa nghe, hub…) thay vì ẩn đĩa như trước (anh Bửu 2026-11-11). Sheet ở cửa sổ riêng nên không
/// đọc được state của `ReaderView`: vỏ tự giữ chiều cao đo được và tự đọc "đang phát" qua projection `TTSWidgetStateReader`
/// (đĩa bìa xoay / nhãn "Đang đọc" ⇄ "Tạm dừng" đổi ngay khi TTS tạm dừng giữa lúc sheet mở).
struct ReaderTTSSameChapterPromptHost: View {
    let prompt: ReaderTTSSameChapterSheet.Prompt
    let onChoose: (ReaderTTSSameChapterSheet.Choice) -> Void

    @StateObject private var ttsState = TTSWidgetStateReader()
    @State private var height: CGFloat = 0

    var body: some View {
        ReaderTTSSameChapterSheet(
            prompt: prompt,
            isPlaying: ttsState.snapshot.isPlaying && ttsState.snapshot.playingBookId == prompt.bookId,
            height: $height,
            onChoose: onChoose
        )
    }
}
