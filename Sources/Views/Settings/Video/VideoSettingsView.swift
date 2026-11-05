import SwiftUI

/// Màn **Video** (Cài đặt › Đọc & Nghe › Video, 1.3.740) — gom cài đặt của trình phát phim:
/// - Nhóm **Khi mở phim**: "Tự phát khi mở phim" (`VideoAutoplayPolicy`, cùng khoá với hàng đầu ngăn kéo `⋯` của trình
///   phát; dời từ section Đọc & Nghe) và "Tắt tiếng khi mở phim" (`VideoMutePolicy`; dời từ màn Nội dung nhạy cảm).
/// - Nhóm **Vuốt xuống trình phát**: kiểu thu nhỏ khi vuốt xuống khung phim ở màn dọc, riêng phim thường / phim 18+
///   (`VideoMinimizePolicy`). Tiện ích ghi đè được ở mục Video của Cấu hình tiện ích. Nút ⌄ luôn thu nhỏ vào hub.
///
/// Mọi giá trị đọc/ghi bằng `@AppStorage` trên đúng khoá tầng nền đọc — đổi là có hiệu lực từ lượt kế tiếp.
struct VideoSettingsView: View {
    /// Mặc định bật — khớp `VideoAutoplayPolicy.isEnabled` (khoá chưa ghi = bật).
    @AppStorage(VideoAutoplayPolicy.defaultsKey) private var autoplaysOnOpen = VideoAutoplayPolicy.defaultValue
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
                minimizePicker("Phim thường", systemImage: "film", selection: $normalMinimize)
                minimizePicker("Phim 18+", systemImage: "eye.slash", selection: $nsfwMinimize)
            } header: {
                SectionHelpHeader("Vuốt xuống trình phát", paragraphs: [
                    "Vuốt xuống khung phim ở màn dọc thì thu nhỏ trình phát. **Thu nhỏ vào hub**: phim chạy nền, điều khiển ở mục Video của hub. **Hình trong hình**: phim chuyển sang khung nổi của hệ thống.",
                    "Không bật được Hình trong hình (phim nhúng, phim chưa tải xong) thì thu nhỏ vào hub. Nút ⌄ luôn thu nhỏ vào hub.",
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
