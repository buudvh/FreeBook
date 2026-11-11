import SwiftUI

/// Hàng "Dịch phụ đề cứng" (OCR, 1.3.830) của ngăn kéo `⋯` trình phát — công tắc nhớ theo tiện ích
/// (`VideoHardSubtitleEngine.setEnabled`). Ẩn khi đang nhúng trang (không lấy được hình của trang).
struct VideoHardSubtitleDrawerRow: View {
    let session: VideoPlaybackSession

    var body: some View {
        if session.embedContent == nil, session.launch != nil {
            let engine = VideoHardSubtitleEngine.shared
            let isOn = engine.isEnabled
            SideDrawerToggleRow(
                "Dịch phụ đề cứng",
                systemImage: "text.viewfinder",
                isOn: Binding(
                    get: { isOn },
                    set: { value in
                        guard value != isOn else { return }
                        MainActor.assumeIsolated { engine.setEnabled(value) }
                    }
                )
            )
        }
    }
}
