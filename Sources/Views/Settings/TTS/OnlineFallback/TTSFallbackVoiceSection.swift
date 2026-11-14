import SwiftUI

/// Mục **"Khi giọng online lỗi"** của Cài đặt TTS (1.3.945) — chỉ khi trình đọc là Google / tiện ích, ngay dưới "Giọng đọc":
/// một hàng dẫn tới màn "Giọng dự phòng" (`TTSFallbackVoiceSettingsView`), chữ phụ là giọng dự phòng hoặc "Không dùng".
/// Giải thích sau nút "?".
struct TTSFallbackVoiceSection: View {
    /// Tăng mỗi lần mục hiện lại (quay về từ màn "Giọng dự phòng") ⇒ đọc lại chữ phụ.
    @State private var refreshToken = 0

    var body: some View {
        Section {
            NavigationLink(destination: TTSFallbackVoiceSettingsView()) {
                HStack(spacing: 12) {
                    Label("Giọng dự phòng", systemImage: "lifepreserver")
                    Spacer(minLength: 8)
                    Text(summary)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            .onAppear { refreshToken += 1 }
        } header: {
            SectionHelpHeader("Khi giọng online lỗi", paragraphs: TTSFallbackVoiceSettingsView.helpParagraphs)
        }
    }

    private var summary: String {
        _ = refreshToken
        guard let engine = TTSOnlineFallbackSettings.engine else { return "Không dùng" }
        return TTSManager.onlineFallbackVoiceTitle(for: engine)
    }
}
