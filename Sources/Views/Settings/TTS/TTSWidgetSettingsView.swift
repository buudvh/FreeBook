import SwiftUI

/// Màn **Widget TTS** (Cài đặt › Đọc & Nghe › Widget TTS, 1.3.796): chọn kiểu widget nổi khi nghe truyện.
/// - **Đĩa nổi** (mặc định): đĩa bìa nép mép, chạm bung viên điều khiển, tự ẩn sau 3 giây — như trước.
/// - **Thanh nghe nhạc**: thanh dáng thanh phát mini nghe nhạc ngay trên thanh tab; thu gọn thành viên nép mép phải. Có
///   thêm hai công tắc: "Thu gọn khi mở Reader" (mặc định bật), "Tự thu gọn sau 5 giây" (mặc định tắt).
///
/// Ghi bằng `@AppStorage` trên đúng khoá `TTSWidgetPreferences` đọc ⇒ widget đổi kiểu ngay (window manager dựng lại
/// container khi `style` đổi).
struct TTSWidgetSettingsView: View {
    @AppStorage(TTSWidgetPreferences.styleKey) private var style: TTSWidgetStyle = TTSWidgetPreferences.defaultStyle
    @AppStorage(TTSWidgetPreferences.collapsesInReaderKey)
    private var collapsesInReader = TTSWidgetPreferences.defaultCollapsesInReader
    @AppStorage(TTSWidgetPreferences.autoCollapseKey) private var autoCollapse = TTSWidgetPreferences.defaultAutoCollapse

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
                    "**Thanh nghe nhạc**: thanh như thanh nghe nhạc, nằm ngay trên thanh tab: bìa, tên truyện, chương đang đọc, phút hẹn giờ còn lại, nút ⏯ ⏭ ⏱ ✕. Chạm bìa hoặc chữ để mở chương đang đọc. Kéo lên xuống để đổi chỗ.",
                    "Bấm » ở mép phải (hoặc vuốt thanh sang ngang) để thu gọn thành viên nép mép phải; chạm đĩa để bung lại."
                ])
            }

            if style == .bar {
                Section {
                    Toggle(isOn: $collapsesInReader) {
                        Label("Thu gọn khi mở Reader", systemImage: "book")
                    }
                    Toggle(isOn: $autoCollapse) {
                        Label("Tự thu gọn sau 5 giây", systemImage: "timer")
                    }
                } header: {
                    SectionHelpHeader("Thanh nghe nhạc", paragraphs: [
                        "**Thu gọn khi mở Reader**: vào màn đọc truyện thì thanh tự thu thành viên để không che chữ; ra khỏi màn đọc thì bung lại nếu trước đó đang bung.",
                        "**Tự thu gọn sau 5 giây**: thanh bung ra mà không chạm gì trong 5 giây thì tự thu gọn."
                    ])
                }
            }
        }
        .backPageTitle("Widget TTS")
    }
}
