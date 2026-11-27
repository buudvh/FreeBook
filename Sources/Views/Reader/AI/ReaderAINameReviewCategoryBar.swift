import SwiftUI

/// Hàng chip lọc theo loại của thẻ duyệt — **chỉ** luồng "Lọc name local" (`ReaderAINameReviewCardView.showsCategoryFilter`,
/// mockup LAC khung 3): "Tất cả N · Nhân danh N · Địa danh N · Tổ chức N · Thuật ngữ N", chỉ hiện nhóm có mục. Chip đang
/// chọn theo kiểu `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn mờ 18%, viền 60%).
///
/// Chip (cùng ô tìm của thẻ) chỉ đổi phần **đang hiện**: "Chọn hết" / "Bỏ chọn" áp lên phần đang hiện, còn số trên chip,
/// số ở tiêu đề thẻ và nút Lưu vẫn tính trên cả danh sách (xem `ReaderAINameReviewCardView+Filtering`). Nhóm đang chọn hết
/// mục (bỏ / chặn hết) ⇒ thẻ coi như "Tất cả" (`active == nil`).
struct ReaderAINameReviewCategoryBar: View {
    let names: [AIExtractedName]
    /// Nhóm đang lọc có hiệu lực (`nil` = Tất cả).
    let active: LocalNameFilter.Category?
    let onSelect: (LocalNameFilter.Category?) -> Void

    var body: some View {
        let counts = Self.counts(of: names)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "Tất cả \(names.count)", isSelected: active == nil) {
                    onSelect(nil)
                }
                ForEach(LocalNameFilter.Category.allCases, id: \.self) { category in
                    if let count = counts[category], count > 0 {
                        chip(title: "\(category.label) \(count)", isSelected: active == category) {
                            onSelect(category)
                        }
                    }
                }
            }
        }
    }

    /// Số mục theo nhóm (nhãn khác bốn nhóm không tính — chỉ hiện ở "Tất cả").
    static func counts(of names: [AIExtractedName]) -> [LocalNameFilter.Category: Int] {
        var counts: [LocalNameFilter.Category: Int] = [:]
        for item in names {
            if let category = LocalNameFilterCategoryBadge.category(forLabel: item.category) {
                counts[category, default: 0] += 1
            }
        }
        return counts
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundColor(isSelected ? .accentColor : .primary)
                .background(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.08))
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isSelected ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
