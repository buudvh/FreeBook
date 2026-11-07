import SwiftUI

/// Màn **Video** (Cài đặt › Đọc & Nghe › Video, 1.3.740) — gom cài đặt của trình phát phim:
/// - Nhóm **Khi mở phim**: "Tự phát khi mở phim" (`VideoAutoplayPolicy`, cùng khoá với hàng đầu ngăn kéo `⋯` của trình
///   phát; dời từ section Đọc & Nghe) và "Tắt tiếng khi mở phim" (`VideoMutePolicy`; dời từ màn Nội dung nhạy cảm).
/// - Nhóm **Khi hết phim**: "Tự sang phim đề xuất" (`VideoAutoNextPolicy`, cùng khoá với hàng thứ hai ngăn kéo `⋯`).
/// - Nhóm **Vuốt xuống trình phát**: kiểu thu nhỏ (hub / cửa sổ nhỏ) khi vuốt xuống khung phim ở màn dọc, riêng phim thường / phim 18+
///   (`VideoMinimizePolicy`). Tiện ích ghi đè được ở mục Video của Cấu hình tiện ích. Nút ⌄ luôn thu nhỏ vào hub.
///
/// Mọi giá trị đọc/ghi bằng `@AppStorage` trên đúng khoá tầng nền đọc — đổi là có hiệu lực từ lượt kế tiếp.
struct VideoSettingsView: View {
    /// Mặc định bật — khớp `VideoAutoplayPolicy.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(VideoAutoplayPolicy.defaultsKey) private var autoplaysOnOpen = VideoAutoplayPolicy.defaultValue
    /// Mặc định bật — khớp `VideoAutoNextPolicy.isEnabled`.
    @AppStorage(VideoAutoNextPolicy.defaultsKey) private var autoNextSuggest = VideoAutoNextPolicy.defaultValue
    /// Cùng khoá `VideoMutePolicy` đọc lúc mở phim mới; mặc định `nsfwOnly`.
    @AppStorage(VideoMutePolicy.defaultsKey) private var mutePolicy: VideoMutePolicy = VideoMutePolicy.defaultValue
    @AppStorage(VideoMinimizePolicy.normalDefaultsKey) private var normalMinimize: VideoMinimizeStyle = VideoMinimizePolicy.defaultValue
    @AppStorage(VideoMinimizePolicy.nsfwDefaultsKey) private var nsfwMinimize: VideoMinimizeStyle = VideoMinimizePolicy.defaultValue

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $autoplaysOnOpen) {
                    Label("Tự phát khi mở phim", systemImage: "play.circle")
                }
                Picker(selection: $mutePolicy) {
                    ForEach(VideoMutePolicy.allCases) { policy in
                        Text(policy.title).tag(policy)
                    }
                } label: {
                    Label("Tắt tiếng khi mở phim", systemImage: "speaker.slash")
                }
                .pickerStyle(.navigationLink)
            } header: {
                SectionHelpHeader("Khi mở phim", paragraphs: [
                    "**Tự phát khi mở phim**: bấm vào phim là phát ngay, đúng tập đang xem dở. Tắt thì khung phim hiện bìa và nút ▶, bấm mới phát; phim khác đang chạy nền vẫn chạy tiếp tới lúc đó.",
                    "**Tắt tiếng khi mở phim**: chỉ áp khi mở một phim mới. Mở lại phim đang thu nhỏ hay đổi tập giữ nguyên tiếng. Phim tắt tiếng thì TTS vẫn đọc tiếp."
                ])
            }

            Section {
                Toggle(isOn: $autoNextSuggest) {
                    Label("Tự sang phim đề xuất", systemImage: "forward.end.circle")
                }
            } header: {
                SectionHelpHeader("Khi hết phim", paragraphs: [
                    "**Tự sang phim đề xuất**: xem hết tập cuối thì phát ngay phim đầu tiên của nhóm đề xuất đầu tiên, ở mọi nơi: màn xem, cửa sổ nhỏ, hub hay khi app chạy nền. Phát luôn dù tắt \"Tự phát khi mở phim\", giữ tiếng như phim vừa xem.",
                    "Phim đã phát trong cùng một chuỗi tự sang bị bỏ qua để không lặp qua lại. Phim nhúng trang web không báo lúc hết phim nên không tự sang."
                ])
            }

            Section {
                minimizePicker("Phim thường", systemImage: "film", selection: $normalMinimize)
                minimizePicker("Phim 18+", systemImage: "eye.slash", selection: $nsfwMinimize)
            } header: {
                SectionHelpHeader("Vuốt xuống trình phát", paragraphs: [
                    "Vuốt xuống khung phim ở màn dọc thì khung phim co theo tay. **Thu nhỏ vào hub**: nhả tay thì phim bay vào nút hub, chạy nền, điều khiển ở mục Video của hub. **Cửa sổ nhỏ**: phim thành cửa sổ nhỏ ở góc dưới phải, nổi trên mọi màn; kéo bám mép trái/phải, thả lên nút hub để thu vào hub, thả vào vòng ✕ ở đáy để tắt, chạm để mở lại.",
                    "Phim nhúng trang web không vào được cửa sổ nhỏ, thu nhỏ vào hub. Nút ⌄ luôn thu nhỏ vào hub. Thu nhỏ không dừng phim; rời app thì phim chỉ phát tiếng.",
                    "Từng tiện ích chỉnh riêng được ở mục Video của Cấu hình tiện ích."
                ])
            }
        }
        .backPageTitle("Video")
    }

    private func minimizePicker(
        _ title: String,
        systemImage: String,
        selection: Binding<VideoMinimizeStyle>
    ) -> some View {
        Picker(selection: selection) {
            ForEach(VideoMinimizeStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
        .pickerStyle(.menu)
    }
}
