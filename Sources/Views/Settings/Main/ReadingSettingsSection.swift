import SwiftUI

/// Section "Đọc & Nghe" của tab Cài đặt (1.3.520): mỗi nhóm cài đặt là **một dòng** dẫn vào màn riêng, chữ phụ
/// bên phải là trạng thái hiện tại. Đọc trạng thái qua `@AppStorage` (cùng khoá các màn con ghi) — không
/// observe `TTSManager` (View không được observe trực tiếp manager). Riêng dòng "Tắt tiếng khi mở phim" là `Picker`
/// ghi thẳng khoá của `VideoMutePolicy`.
struct ReadingSettingsSection: View {
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// `TTSManager` ghi khoá này mỗi khi đổi engine; mặc định `"system"` giống `TTSManager.init`.
    @AppStorage("ttsTool") private var ttsTool = "system"
    /// Mặc định `true` khớp `WebContentSettings.registerDefaults()`.
    @AppStorage(WebContentSettings.adBlockEnabledKey) private var adBlockEnabled = true
    /// Cùng khoá `VideoMutePolicy` đọc lúc mở phim mới; mặc định `nsfwOnly`.
    @AppStorage(VideoMutePolicy.defaultsKey) private var videoMutePolicy: VideoMutePolicy = VideoMutePolicy.defaultValue

    var body: some View {
        Section(header: Text("Đọc & Nghe")) {
            NavigationLink(destination: TranslationSettingsView()) {
                LabeledContent {
                    Text(isTranslationEnabled ? "Đang bật" : "Tắt")
                } label: {
                    Label("Cài đặt dịch thuật", systemImage: "character.book.closed")
                }
            }
            NavigationLink(destination: TTSSettingsHubView()) {
                LabeledContent {
                    Text(TTSSettingsHubView.engineName(for: ttsTool))
                } label: {
                    Label("Nghe truyện (TTS)", systemImage: "headphones")
                }
            }
            NavigationLink(destination: AISettingsView()) {
                Label("Trợ lý AI", systemImage: "sparkles")
            }
            NavigationLink(destination: BrowserSettingsView()) {
                LabeledContent {
                    Text(adBlockEnabled ? "Chặn QC: Bật" : "Chặn QC: Tắt")
                } label: {
                    Label("Trình duyệt", systemImage: "globe")
                }
            }
            Picker(selection: $videoMutePolicy) {
                ForEach(VideoMutePolicy.allCases) { policy in
                    Text(policy.title).tag(policy)
                }
            } label: {
                Label("Tắt tiếng khi mở phim", systemImage: "speaker.slash")
            }
            .pickerStyle(.navigationLink)
        }
    }
}
