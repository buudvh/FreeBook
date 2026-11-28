import SwiftUI

/// Hàng **"Phân loại"** ở màn Sửa từ của màn duyệt Lọc name local (2026-11-28, mockup
/// https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2 khung M2, plan mục C11): nhãn "Phân loại" + nút `?`, bên phải ghi nhóm lúc
/// lọc khi đã đổi khác ("Lúc lọc: Nhân danh"), dưới là bốn ô Nhân danh / Địa danh / Tổ chức / Thuật ngữ có chấm màu của badge
/// nhóm (`LocalNameFilterCategoryBadge.color(for:)`). Mọi name trừ họ tộc (cùng điều kiện hàng Tiền tố / Hậu tố).
///
/// Tự dựng bốn ô thay `Picker(.segmented)`: đoạn của `UISegmentedControl` tô ảnh một màu nên không có chấm màu. Chạm ô đang
/// chọn không làm gì; đổi ô ⇒ `onSelect` (màn duyệt đổi badge + chip lọc, ghép lại nghĩa theo nhóm mới).
struct LocalNameFilterReviewCategoryRow: View {
    typealias Category = LocalNameFilter.Category

    /// Nhóm đang hiện ở badge; `nil` = nhãn ngoài bốn nhóm (không ô nào chọn).
    let selection: Category?
    /// Nhóm lúc lọc nếu lượt duyệt này còn nhớ (đã đổi ít nhất một lần).
    let original: Category?
    let onSelect: (Category) -> Void

    private static let helpParagraphs: [String] = [
        "Đổi nhóm của name này **trong lượt duyệt**: badge và số trên chip lọc đổi theo, hàng Tiền tố / Hậu tố gợi ý loại theo nhóm mới.",
        "Nghĩa do máy ghép được ghép lại theo nhóm mới (古赫密斯语: Nhân danh ⇒ Thuật ngữ ra \"cổ Hermes ngữ\"); nghĩa đã tự sửa giữ nguyên. Gói tạm nhớ nhóm mới.",
        "Lần lọc sau bộ lọc phân loại lại từ đầu — lựa chọn ở đây không được nhớ."
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 2) {
                Text("Phân loại")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                SectionHelpButton(
                    accessibilityLabel: "Giải thích Phân loại",
                    paragraphs: Self.helpParagraphs.map { LocalizedStringKey($0) }
                )
                Spacer(minLength: 0)
                if let original, original != selection {
                    Text(verbatim: "Lúc lọc: \(original.label)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 2) {
                ForEach(Category.allCases, id: \.self) { category in
                    cell(category)
                }
            }
            .padding(2)
            .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ category: Category) -> some View {
        let isSelected = category == selection
        return Button {
            guard !isSelected else { return }
            onSelect(category)
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(LocalNameFilterCategoryBadge.color(for: category))
                    .frame(width: 7, height: 7)
                Text(verbatim: category.label)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(isSelected ? Color.secondary.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(category.label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
