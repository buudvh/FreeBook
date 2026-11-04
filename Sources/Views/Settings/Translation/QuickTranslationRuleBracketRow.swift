import SwiftUI

/// Một hàng của màn Bộ ngoặc (`QuickTranslationRuleBracketListView`), theo kiểu hàng danh sách 1.3.636:
/// dòng 1 `.headline` là cặp ngoặc, dòng 2 `.subheadline` màu phụ là tên (cặp tắt thêm " · đang tắt" và mờ),
/// cụm icon `[Sửa] [Tắt/Bật] [Xoá]` cùng cỡ và thứ tự với `QuickTranslationRuleEntryRow`.
///
/// `isEditable == false` (truyện đang theo bộ chung) ⇒ chỉ xem, không có icon.
struct QuickTranslationRuleBracketRow: View {
    let pair: QuickTranslationRuleBracketPair
    let isEditable: Bool
    let onEdit: () -> Void
    let onToggle: () -> Void
    let onDelete: () -> Void

    /// Cặp ngoặc dạng chữ, vd "【 】" — dòng 1 của hàng và phần đuôi nhãn trợ năng.
    private var glyphs: String { "\(pair.open) \(pair.close)" }

    private var subtitle: String {
        let name = pair.name.isEmpty ? "Không tên" : pair.name
        return pair.isEnabled ? name : name + " · đang tắt"
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: glyphs)
                    .font(.headline)
                Text(verbatim: subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .opacity(pair.isEnabled ? 1 : 0.5)

            Spacer(minLength: 8)

            if isEditable {
                actionIcons
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    private var actionIcons: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Sửa cặp \(glyphs)")

            Button(action: onToggle) {
                Image(systemName: pair.isEnabled ? "pause.circle" : "play.circle")
                    .foregroundColor(pair.isEnabled ? .orange : .green)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(pair.isEnabled ? "Tắt cặp \(glyphs)" : "Bật cặp \(glyphs)")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(.red)
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Xoá cặp \(glyphs)")
        }
    }
}
