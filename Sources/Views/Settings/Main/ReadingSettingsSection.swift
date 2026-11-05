import SwiftUI

/// Section "Đọc & Nghe" của tab Cài đặt (1.3.520): mỗi nhóm cài đặt là **một dòng** dẫn vào màn riêng, chữ phụ
/// bên phải là trạng thái hiện tại. Đọc trạng thái qua `@AppStorage` (cùng khoá các màn con ghi) — không
/// observe `TTSManager` (View không được observe trực tiếp manager). Cài đặt phim ("Tự phát khi mở phim", "Tắt tiếng khi
/// mở phim", vuốt xuống trình phát) nằm ở màn riêng `VideoSettingsView` (1.3.740). Ngoại lệ là công tắc "Mở lại truyện
/// đọc gần nhất" (1.3.716, `ReaderSessionRestoreStore`) nằm ngay trong section, giải thích ở nút "?" của tiêu đề.
struct ReadingSettingsSection: View {
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// `TTSManager` ghi khoá này mỗi khi đổi engine; mặc định `"system"` giống `TTSManager.init`.
    @AppStorage("ttsTool") private var ttsTool = "system"
    /// Mặc định `true` khớp `WebContentSettings.registerDefaults()`.
    @AppStorage(WebContentSettings.adBlockEnabledKey) private var adBlockEnabled = true
    /// Mặc định bật — khớp `ReaderSessionRestoreStore.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(ReaderSessionRestoreStore.enabledKey) private var restoresReaderOnLaunch = ReaderSessionRestoreStore.defaultEnabled

    var body: some View {
        Section {
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
            NavigationLink(destination: VideoSettingsView()) {
                Label("Video", systemImage: "play.rectangle")
            }
            Toggle(isOn: $restoresReaderOnLaunch) {
                Label("Mở lại truyện đọc gần nhất", systemImage: "arrow.uturn.backward.circle")
            }
        } header: {
            SectionHelpHeader("Đọc & Nghe", paragraphs: [
                "**Mở lại truyện đọc gần nhất**: mở app là tự vào lại truyện, truyện tranh hoặc phim đọc/xem gần nhất, đúng chương, đúng chỗ.",
                "Mục 18+ được bỏ qua, lấy mục gần nhất kế tiếp. TTS và phim không tự phát.",
                "Lần mở lại trước bị tắt trong 10 giây đầu thì lần này bỏ qua."
            ])
        }
    }
}
