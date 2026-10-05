import SwiftUI

/// Hàng chọn "Số lượng chương" dùng chung cho sheet tải/xuất truyện (`TaskOptionsSheet`) và sheet
/// quét tên riêng (`ReaderAIBatchPromptSheet`).
///
/// Cố ý tách thành **hai hàm rời** — `optionPicker` và `customRow` — rồi gọi thẳng trong builder của
/// `Form`, thay vì gộp vào một `View`/`@ViewBuilder func` duy nhất: `Form`/`List` chỉ tách hàng cho
/// những view nằm **trực tiếp** trong builder của nó, nên gói hai hàng vào một view sẽ dồn picker và
/// thanh kéo vào cùng một ô. Vì cùng lý do, điều kiện hiện hàng thanh kéo cũng đặt ở call site để cấu
/// trúc hàng giống hệt trước khi tách.
enum ChapterLimitPicker {
    /// Picker các mốc số chương (Tất cả / 50 / 100 / 200 / 500 / 1000 / Tuỳ chọn).
    static func optionPicker(option: Binding<ChapterLimitOption>) -> some View {
        Picker("Số lượng chương", selection: option) {
            ForEach(ChapterLimitOption.allCases, id: \.self) { item in
                Text(item.title).tag(item)
            }
            Text(ChapterLimitOption.custom.title).tag(ChapterLimitOption.custom)
        }
        .pickerStyle(.menu)
    }

    /// Hàng "Tuỳ chọn": thanh kéo 1...1000 bước 1, hai bên là nút -/+ đổi từng chương một cho
    /// người dùng chốt số chính xác (kéo tay khó dừng đúng con số muốn).
    static func customRow(customLimit: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Số chương tuỳ chọn")
                Spacer()
                Text("\(customLimit.wrappedValue)")
                    .font(.body.monospacedDigit())
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                stepButton(systemName: "minus", delta: -1, customLimit: customLimit)
                Slider(
                    value: Binding(
                        get: { Double(customLimit.wrappedValue) },
                        set: { customLimit.wrappedValue = ChapterLimitOption.clampCustom(Int($0.rounded())) }
                    ),
                    in: customSliderRange,
                    step: 1
                )
                .tint(.white)
                stepButton(systemName: "plus", delta: 1, customLimit: customLimit)
            }
        }
        .padding(.vertical, 4)
    }

    /// Dải của thanh kéo, dựng ở một chỗ vì viết `a...b` xuống dòng trong danh sách tham số sẽ bị
    /// Swift đọc thành toán tử tiền tố `...b` (một tham số rời), không phải `ClosedRange`.
    private static var customSliderRange: ClosedRange<Double> {
        let lower = Double(ChapterLimitOption.customRange.lowerBound)
        let upper = Double(ChapterLimitOption.customRange.upperBound)
        return lower...upper
    }

    private static func stepButton(systemName: String, delta: Int, customLimit: Binding<Int>) -> some View {
        Button {
            customLimit.wrappedValue = ChapterLimitOption.clampCustom(customLimit.wrappedValue + delta)
        } label: {
            Image(systemName: systemName)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        // `.borderless` để nút không biến cả hàng của Form thành một vùng bấm duy nhất.
        .buttonStyle(.borderless)
        .disabled(ChapterLimitOption.clampCustom(customLimit.wrappedValue + delta) == customLimit.wrappedValue)
        .accessibilityLabel(delta > 0 ? "Tăng một chương" : "Giảm một chương")
    }
}

extension ChapterLimitOption {
    /// Kẹp giá trị thanh kéo "Tuỳ chọn" vào `customRange` — dùng chung cho cả hai sheet.
    static func clampCustom(_ value: Int) -> Int {
        min(max(value, customRange.lowerBound), customRange.upperBound)
    }
}
