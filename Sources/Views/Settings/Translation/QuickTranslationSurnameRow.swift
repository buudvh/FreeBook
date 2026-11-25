import SwiftUI

/// Một hàng của màn **Danh sách họ** (`QuickTranslationSurnameListView`, 1.3.1062), kiểu VP/Name như
/// `QuickTranslationRuleBracketRow`: dòng 1 chữ Hán `.headline`, dòng 2 âm `.subheadline` màu phụ kèm trạng thái ("tự
/// thêm" / "đã sửa" / "đang tắt" — hàng tắt mờ 50%), cụm icon `[Tắt/Bật] [Xoá]`, **không** icon bút chì: chạm thân hàng mở
/// sheet sửa. Không bọc cả hàng trong `Button` (List sẽ kích hoạt mọi nút); trợ năng có thao tác "Sửa".
struct QuickTranslationSurnameRow: View {
    let entry: QuickTranslationSurnameEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    private var subtitle: String {
        var parts = [entry.reading]
        if entry.origin == .userAdded { parts.append("tự thêm") }
        if entry.isEdited { parts.append("đã sửa") }
        if !entry.isEnabled { parts.append("đang tắt") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .center) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: entry.key)
                        .font(.headline)
                    Text(verbatim: subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .opacity(entry.isEnabled ? 1 : 0.5)

                Spacer(minLength: 8)
            }
            .contentShape(Rectangle())
            .onTapGesture { onEdit() }

            HStack(spacing: 10) {
                Button(action: onToggle) {
                    Image(systemName: entry.isEnabled ? "pause.circle" : "play.circle")
                        .foregroundColor(entry.isEnabled ? .orange : .green)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(entry.isEnabled ? "Tắt họ \(entry.key)" : "Bật họ \(entry.key)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Xoá họ \(entry.key)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: "Sửa") { onEdit() }
    }
}
