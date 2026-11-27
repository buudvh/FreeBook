import SwiftUI

/// Một nhóm từ điển trong màn "Quản lý nghĩa từ": nhãn (Name / VP / Pronoun + Riêng / Chung) bên trái, các chip nghĩa tràn dòng
/// bên phải, chip `+` ở cuối; chip đang chọn thì hiện ô sửa ngay dưới nhóm kèm hai nút đổi chỗ sang trái / phải.
///
/// View này không giữ trạng thái: bản nháp, chip đang chọn và focus đều do `ManageDefinitionsView` giữ.
struct ManageDefinitionGroupView: View {
    private static let labelWidth: CGFloat = 52
    private static let labelSpacing: CGFloat = 8

    let dictionaryName: String
    let scopeName: String
    let isBookScope: Bool
    let rows: [ManageDefinitionsDraft.Row]
    let selectedRowId: UUID?
    let editorText: Binding<String>
    let editorFocus: FocusState<Bool>.Binding
    let onTapRow: (ManageDefinitionsDraft.Row) -> Void
    let onToggleDeleted: (ManageDefinitionsDraft.Row) -> Void
    let onAdd: () -> Void
    /// Đổi chỗ chip đang chọn: `-1` sang trái, `+1` sang phải.
    let onMoveSelected: (Int) -> Void
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: Self.labelSpacing) {
                groupLabel
                // Chip đã tự chừa `badgeInset` bên phải ⇒ khe nhìn thấy giữa hai chip = spacing + badgeInset.
                FlowLayout(spacing: 2) {
                    ForEach(rows) { row in
                        ManageDefinitionChipView(
                            text: row.text,
                            isPrimary: row.id == primaryRowId,
                            isSelected: row.id == selectedRowId,
                            isDeleted: row.isDeleted,
                            onTap: { onTapRow(row) },
                            onToggleDeleted: { onToggleDeleted(row) }
                        )
                    }
                    addChip
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let index = selectedIndex {
                editor(index: index)
                    .padding(.leading, Self.labelWidth + Self.labelSpacing)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    /// Nghĩa đứng đầu trong các nghĩa sẽ được ghi — cùng điều kiện với `ManageDefinitionsDraft.activeMeanings`.
    private var primaryRowId: UUID? {
        rows.first { row in
            guard !row.isDeleted else { return false }
            return row.preservesEmpty || !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }?.id
    }

    private var selectedIndex: Int? {
        guard let selectedRowId else { return nil }
        return rows.firstIndex { $0.id == selectedRowId }
    }

    private var groupLabel: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(dictionaryName)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8) // "Pronoun" vừa sát cột nhãn 52pt khi chữ hệ thống to hơn mặc định
            Text(scopeName)
                .font(.caption2)
                .foregroundColor(isBookScope ? .accentColor : .secondary)
        }
        .frame(width: Self.labelWidth, alignment: .leading)
        .padding(.top, ManageDefinitionChipView.badgeInset + 3)
        .accessibilityElement(children: .combine)
    }

    private var addChip: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: ManageDefinitionChipView.chipHeight, height: ManageDefinitionChipView.chipHeight)
                .overlay(
                    Circle().strokeBorder(
                        Color.accentColor.opacity(0.6),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .padding(.top, ManageDefinitionChipView.badgeInset)
        .accessibilityLabel("Thêm nghĩa vào \(dictionaryName) \(scopeName)")
    }

    private func editor(index: Int) -> some View {
        HStack(spacing: 0) {
            TextField("Nghĩa…", text: editorText)
                .font(.body)
                .textInputAutocapitalization(.never)
                .submitLabel(.done)
                .focused(editorFocus)
                .onSubmit(onSubmit)

            moveButton("arrow.left", label: "Đưa nghĩa sang trái", enabled: index > 0) {
                onMoveSelected(-1)
            }
            moveButton("arrow.right", label: "Đưa nghĩa sang phải", enabled: index < rows.count - 1) {
                onMoveSelected(1)
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 2)
        .frame(height: 40)
        .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
        .padding(.trailing, ManageDefinitionChipView.badgeInset)
    }

    private func moveButton(
        _ systemName: String,
        label: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(enabled ? .primary : Color.gray.opacity(0.35))
                .frame(width: 34, height: 38)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
