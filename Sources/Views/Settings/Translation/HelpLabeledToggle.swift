import SwiftUI

/// Hàng công tắc có nút "?" **ngay cạnh tên** (thay dòng chữ giải thích luôn hiện dưới tên công tắc).
///
/// Cố ý **không** đặt nút "?" trong nhãn của `Toggle`: nhãn `Toggle` trong `Form` không phải chỗ cho nút lồng — chạm
/// có thể rơi xuống công tắc. Hàng là `HStack` [tên][?] … [công tắc ẩn nhãn]; nhãn trợ năng của công tắc vẫn là tên.
/// Nút "?" là `SectionHelpButton` (popover, `.borderless`) như ở tiêu đề section.
struct HelpLabeledToggle: View {
    let title: String
    var titleFont: Font = .body
    let help: [LocalizedStringKey]
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
                .font(titleFont)
            SectionHelpButton(accessibilityLabel: "Giải thích \(title)", paragraphs: help)
            Spacer(minLength: 8)
            Toggle(title, isOn: $isOn)
                .labelsHidden()
        }
    }
}
