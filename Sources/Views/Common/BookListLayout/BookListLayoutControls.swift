import SwiftUI

/// Thanh chọn kiểu (Danh sách · Lưới · Chỉ bìa) + bước "Số cột" (kiểu lưới) hoặc thanh "Cỡ dòng" (kiểu Danh sách)
/// của **một** scope. Dùng chung cho sheet nhanh (`BookListLayoutSheet`) và màn Cài đặt
/// (`BookListLayoutSettingsView`); trong `Form` mỗi control là một hàng.
///
/// Đọc trạng thái **trong lượt vẽ** (bảng là `@Observable` nên ghi xong là vẽ lại); closure của `Binding` chỉ giữ
/// giá trị đã chụp, không chạm singleton `@MainActor` từ ngữ cảnh không cô lập — cùng lối với
/// `ExtensionConfigView+History`.
struct BookListLayoutControls: View {
    let scope: BookListLayoutScope

    var body: some View {
        let layout = BookListLayoutPreferences.shared.layout(for: scope)

        Picker("Kiểu hiển thị", selection: modeBinding(current: layout.mode)) {
            ForEach(BookListLayoutMode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()

        if layout.mode.isGrid {
            Stepper(value: columnsBinding(current: layout.columns), in: BookListLayoutPreferences.columnRange) {
                HStack {
                    Text("Số cột")
                    Spacer()
                    Text("\(layout.columns)")
                        .monospacedDigit()
                        .foregroundColor(.secondary)
                }
            }
        } else {
            rowSizeControl(layout.rowSize)
        }
    }

    /// "Cỡ dòng" của kiểu Danh sách: thanh trượt 7 nấc, hai đầu là chữ A nhỏ / A to như cỡ chữ của iOS.
    private func rowSizeControl(_ size: BookListRowSize) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Cỡ dòng")
                Spacer()
                Text("\(size.level)/\(BookListRowSize.range.upperBound)" + (size.isDefault ? " · mặc định" : ""))
                    .monospacedDigit()
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                Text("A")
                    .font(.system(size: 11))
                Slider(
                    value: rowSizeBinding(current: size.level),
                    in: Double(BookListRowSize.range.lowerBound)...Double(BookListRowSize.range.upperBound),
                    step: 1
                )
                .accessibilityLabel("Cỡ dòng")
                Text("A")
                    .font(.system(size: 18))
            }
        }
    }

    private func modeBinding(current: BookListLayoutMode) -> Binding<BookListLayoutMode> {
        let scope = scope
        return Binding(
            get: { current },
            set: { value in
                MainActor.assumeIsolated { BookListLayoutPreferences.shared.setMode(value, for: scope) }
            }
        )
    }

    private func rowSizeBinding(current: Int) -> Binding<Double> {
        let scope = scope
        return Binding(
            get: { Double(current) },
            set: { value in
                MainActor.assumeIsolated { BookListLayoutPreferences.shared.setRowSize(Int(value.rounded()), for: scope) }
            }
        )
    }

    private func columnsBinding(current: Int) -> Binding<Int> {
        let scope = scope
        return Binding(
            get: { current },
            set: { value in
                MainActor.assumeIsolated { BookListLayoutPreferences.shared.setColumns(value, for: scope) }
            }
        )
    }
}
