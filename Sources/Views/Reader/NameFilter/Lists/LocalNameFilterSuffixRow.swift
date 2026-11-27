import SwiftUI

/// Một hàng của màn **Đuôi địa danh, tổ chức, thuật ngữ** (`LocalNameFilterSuffixListView`), khuôn
/// `QuickTranslationSurnameRow`:
/// dòng 1 chữ Hán `.headline`, dòng 2 "nghĩa · loại · trước tên|sau tên" `.subheadline` màu phụ kèm trạng thái ("tự thêm" /
/// "đã sửa" / "đang tắt" — hàng tắt mờ 50%), cụm icon `[Tắt/Bật] [Xoá]`, không icon bút chì: chạm thân hàng mở sheet sửa.
/// Không bọc cả hàng trong `Button` (List sẽ kích hoạt mọi nút); trợ năng có thao tác "Sửa".
struct LocalNameFilterSuffixRow: View {
    let entry: LocalNameFilterSuffixEntry
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    /// Nhãn loại — dùng chung cho tab của màn danh sách và ô Loại của sheet sửa = nhãn nhóm name của đuôi
    /// (`sect` hiện là "Tổ chức").
    static func kindLabel(_ kind: LocalNameFilter.SuffixKind) -> String {
        kind.category.label
    }

    /// Nhãn vị trí ở dòng 2 (chữ thường, như mockup).
    static func positionLabel(_ position: LocalNameFilter.MeaningPosition) -> String {
        switch position {
        case .before: return "trước tên"
        case .after: return "sau tên"
        }
    }

    private var subtitle: String {
        var parts = [entry.meaning, Self.kindLabel(entry.kind), Self.positionLabel(entry.position)]
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
                .accessibilityLabel(entry.isEnabled ? "Tắt đuôi \(entry.key)" : "Bật đuôi \(entry.key)")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.subheadline)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Xoá đuôi \(entry.key)")
            }
        }
        .padding(.vertical, 2)
        .accessibilityAction(named: "Sửa") { onEdit() }
    }
}
