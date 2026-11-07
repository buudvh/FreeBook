import SwiftUI

/// Thanh trượt chọn nấc cỡ: dòng "Tên ··· N/7 · mặc định", dưới là thanh trượt bước 1 với chữ A nhỏ / A to ở hai
/// đầu như cỡ chữ của iOS. Dùng cho "Cỡ dòng" (`BookListLayoutControls`) và cỡ từng bố cục trang Khám phá
/// (`ExploreLayoutSizeControls`); trong `Form` là một hàng.
///
/// Nhận nấc đã đọc **trong lượt vẽ** của View cha; `onChange` chạy trên main actor khi kéo sang nấc khác — closure
/// của `Binding` chỉ giữ giá trị đã chụp, cùng lối với `BookListLayoutControls`.
struct LayoutLevelSlider: View {
    let title: String
    let level: Int
    let range: ClosedRange<Int>
    let defaultLevel: Int
    let onChange: @MainActor @Sendable (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text("\(level)/\(range.upperBound)" + (level == defaultLevel ? " · mặc định" : ""))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Text("A")
                    .font(.system(size: 11))
                Slider(
                    value: levelBinding,
                    in: Double(range.lowerBound)...Double(range.upperBound),
                    step: 1
                )
                .accessibilityLabel(title)
                Text("A")
                    .font(.system(size: 18))
            }
        }
    }

    private var levelBinding: Binding<Double> {
        let current = level
        let onChange = onChange
        return Binding(
            get: { Double(current) },
            set: { value in
                MainActor.assumeIsolated { onChange(Int(value.rounded())) }
            }
        )
    }
}
