import SwiftUI

/// Màn **Widget TTS** (Cài đặt › Đọc & Nghe › Widget TTS, 1.3.796): chọn kiểu widget nổi khi nghe truyện.
/// - **Đĩa nổi** (mặc định): đĩa bìa nép mép, chạm bung viên điều khiển, tự ẩn sau 3 giây — như trước.
/// - **Đĩa góc dưới** (1.3.808, thay "Thanh nghe nhạc"): đĩa xoay góc dưới phải dùng chung với trình nghe nhạc
///   (`MediaDiscWindowManager`), chạm mở sheet điều khiển nhanh.
///
/// Ghi bằng `@AppStorage` trên đúng khoá `TTSWidgetPreferences` đọc ⇒ widget đổi kiểu ngay.
struct TTSWidgetSettingsView: View {
    @AppStorage(TTSWidgetPreferences.styleKey) private var style: TTSWidgetStyle = TTSWidgetPreferences.defaultStyle

    var body: some View {
        Form {
            Section {
                Picker(selection: $style) {
                    ForEach(TTSWidgetStyle.allCases) { item in
                        Text(item.title).tag(item)
                    }
                } label: {
                    Label("Kiểu widget", systemImage: "rectangle.bottomthird.inset.filled")
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SectionHelpHeader("Kiểu widget", paragraphs: [
                    "**Đĩa nổi**: đĩa bìa nép mép màn hình, chạm để bung nút điều khiển, tự ẩn sau 3 giây. Kéo đi đâu cũng được.",
                    "**Đĩa góc dưới**: đĩa bìa xoay ở góc dưới bên phải, cùng chỗ với đĩa khi nghe nhạc, nổi trên mọi màn (đứng ngay trên nút \"+\", thanh tab hay nút tai nghe của Reader). Chạm đĩa để mở bảng điều khiển nhanh; chạm bìa hoặc tên truyện trong bảng để mở chương đang đọc."
                ])
            }
        }
        .backPageTitle("Widget TTS")
    }
}
