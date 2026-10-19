import SwiftUI

/// Thanh chọn kiểu (Danh sách · Lưới · Chỉ bìa) + bước "Số cột" của **một** scope. Dùng chung cho sheet nhanh
/// (`BookListLayoutSheet`) và màn Cài đặt (`BookListLayoutSettingsView`); trong `Form` mỗi control là một hàng.
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
