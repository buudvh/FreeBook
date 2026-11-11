import SwiftUI

/// Các hàng phụ đề cứng (OCR) của ngăn kéo `⋯` trình phát (1.3.830; 1.3.840):
/// - Công tắc **"Đọc phụ đề cứng"** nhớ theo tiện ích (`VideoHardSubtitleEngine.setEnabled`). Ẩn khi đang nhúng trang.
/// - Đang đọc mà phim tắt dịch ⇒ hàng "Phim đang tắt dịch" mở sheet "Dịch phụ đề" (dịch theo công tắc dịch của phim, như
///   truyện chữ / truyện tranh).
/// - Đang đọc ⇒ lưới kiểu hiển thị **Gốc / Bản dịch / Song ngữ**, cùng khoá với phụ đề mềm (`MediaCaptionDisplayMode`).
struct VideoHardSubtitleDrawerRow: View {
    let session: VideoPlaybackSession
    let controller: VideoPlayerController

    @AppStorage(MediaCaptionDisplayMode.videoDefaultsKey) private var displayMode = MediaCaptionDisplayMode.defaultValue

    var body: some View {
        if session.embedContent == nil, session.launch != nil {
            let engine = VideoHardSubtitleEngine.shared
            let isOn = engine.isEnabled
            SideDrawerToggleRow(
                "Đọc phụ đề cứng",
                systemImage: "text.viewfinder",
                isOn: Binding(
                    get: { isOn },
                    set: { value in
                        guard value != isOn else { return }
                        MainActor.assumeIsolated { engine.setEnabled(value) }
                    }
                )
            )
            if isOn {
                if !engine.isTranslationActive {
                    SideDrawerActionRow("Phim đang tắt dịch", glyph: .translate, detail: "Bật") {
                        controller.showsCaptionTranslationSheet = true
                    }
                }
                SideDrawerSectionHeader("Phụ đề cứng hiện")
                VideoPlayerOptionGrid(options: MediaCaptionDisplayMode.allCases.map { mode in
                    VideoPlayerOptionGrid.Option(id: mode.rawValue, title: mode.title, isSelected: mode == displayMode) {
                        displayMode = mode
                    }
                })
            }
        }
    }
}
