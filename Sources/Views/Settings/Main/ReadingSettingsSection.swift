import SwiftUI

/// Section "Đọc & Nghe" của tab Cài đặt (1.3.520): mỗi nhóm cài đặt là **một dòng** dẫn vào màn riêng, chữ phụ
/// bên phải là trạng thái hiện tại. Đọc trạng thái qua `@AppStorage` (cùng khoá các màn con ghi) — không
/// observe `TTSManager` (View không được observe trực tiếp manager). "Tắt tiếng khi mở phim" đã chuyển sang màn
/// Nội dung nhạy cảm (`NsfwSettingsView`). Ngoại lệ là hai công tắc nằm ngay trong section, giải thích ở nút "?" của
/// tiêu đề: "Mở lại truyện đọc gần nhất" (1.3.716, `ReaderSessionRestoreStore`) và "Tự phát khi mở phim"
/// (`VideoAutoplayPolicy`, cùng khoá với hàng đầu ngăn kéo `⋯` của trình phát).
struct ReadingSettingsSection: View {
    @AppStorage("isTranslationEnabled") private var isTranslationEnabled = false
    /// `TTSManager` ghi khoá này mỗi khi đổi engine; mặc định `"system"` giống `TTSManager.init`.
    @AppStorage("ttsTool") private var ttsTool = "system"
    /// Mặc định `true` khớp `WebContentSettings.registerDefaults()`.
    @AppStorage(WebContentSettings.adBlockEnabledKey) private var adBlockEnabled = true
    /// Mặc định bật — khớp `ReaderSessionRestoreStore.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(ReaderSessionRestoreStore.enabledKey) private var restoresReaderOnLaunch = ReaderSessionRestoreStore.defaultEnabled
    /// Mặc định bật — khớp `VideoAutoplayPolicy.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(VideoAutoplayPolicy.defaultsKey) private var autoplaysVideoOnOpen = VideoAutoplayPolicy.defaultValue

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
            Toggle(isOn: $restoresReaderOnLaunch) {
                Label("Mở lại truyện đọc gần nhất", systemImage: "arrow.uturn.backward.circle")
            }
            Toggle(isOn: $autoplaysVideoOnOpen) {
                Label("Tự phát khi mở phim", systemImage: "play.circle")
            }
        } header: {
            SectionHelpHeader("Đọc & Nghe", paragraphs: [
                "**Mở lại truyện đọc gần nhất**: mở app là tự vào lại truyện, truyện tranh hoặc phim đọc/xem gần nhất, đúng chương, đúng chỗ.",
                "Mục 18+ được bỏ qua, lấy mục gần nhất kế tiếp. TTS và phim không tự phát.",
                "Lần mở lại trước bị tắt trong 10 giây đầu thì lần này bỏ qua.",
                "**Tự phát khi mở phim**: bấm vào phim là phát ngay, đúng tập đang xem dở. Tắt thì khung phim hiện bìa và nút ▶, bấm mới phát; phim khác đang chạy nền vẫn chạy tiếp tới lúc đó."
            ])
        }
    }
}
