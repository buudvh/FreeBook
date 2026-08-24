import SwiftUI

/// Một hàng nghĩa trong màn "Quản lý nghĩa từ": ô nhập sửa trực tiếp, kèm nút đổi vị trí lên/xuống,
/// nút chèn ô trống phía trên và nút xoá (xoá mềm — bấm lại nút hoàn tác là lấy lại).
struct ManageDefinitionRowView: View {
    @Binding var text: String
    let isDeleted: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onInsertAbove: () -> Void
    let onToggleDeleted: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            TextField("Nghĩa...", text: $text)
                .font(.body)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .strikethrough(isDeleted)
                .foregroundColor(isDeleted ? .secondary : .primary)
                .disabled(isDeleted)

            iconButton(
                "chevron.up",
                color: canMoveUp ? .blue : .gray.opacity(0.35),
                label: "Đưa nghĩa lên trên",
                action: onMoveUp
            )
            .disabled(!canMoveUp)

            iconButton(
                "chevron.down",
                color: canMoveDown ? .blue : .gray.opacity(0.35),
                label: "Đưa nghĩa xuống dưới",
                action: onMoveDown
            )
            .disabled(!canMoveDown)

            if isDeleted {
                iconButton(
                    "arrow.uturn.backward",
                    color: .green,
                    label: "Hoàn tác xoá nghĩa",
                    action: onToggleDeleted
                )
            } else {
                iconButton("plus", color: .blue, label: "Chèn ô trống phía trên", action: onInsertAbove)
                iconButton("trash", color: .red, label: "Xoá nghĩa", action: onToggleDeleted)
            }
        }
    }

    /// Nút icon hẹp: bốn nút phải nằm cùng hàng với ô nhập trên màn iPhone nên dùng `.borderless`
    /// (để cả hàng của `List` không thành một vùng bấm) và cỡ chữ nhỏ.
    private func iconButton(
        _ systemName: String,
        color: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.footnote)
                .foregroundColor(color)
                .frame(width: 26, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
    }
}
