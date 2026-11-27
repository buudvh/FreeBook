import SwiftUI

/// Section "Loại cần tìm" của sheet "Lọc name local" (mockup LAC khung 1): bốn chip Nhân danh / Địa danh / Tổ chức / Thuật
/// ngữ (`LocalNameFilter.Category.allCases`), chấm màu = màu badge (`LocalNameFilterCategoryBadge.color(for:)`). Mặc định
/// bật cả bốn, không tắt được chip cuối cùng. Nhớ giữa các lần mở bằng `@AppStorage` `localNameFilterCategories` (chuỗi
/// `rawValue` nối dấu phẩy); bấm "Bắt đầu lọc" ⇒ `LocalNameFilter.Configuration.categories`.
///
/// Chip đang bật theo kiểu `ExtensionKindFilterBar` (chữ màu nhấn, nền nhấn mờ 18%, viền 60%) + dấu ✓. Mỗi chip là
/// `Button` `.plain` riêng trong cùng một hàng `Form` — không để kiểu mặc định (cả hàng bấm là mọi nút cùng chạy).
extension LocalNameFilterSheet {
    /// Nhóm đang bật; chuỗi rỗng / hỏng / không còn nhóm nào ⇒ cả bốn.
    var selectedCategories: Set<LocalNameFilter.Category> {
        let parsed = Set(categoriesRaw.split(separator: ",").compactMap {
            LocalNameFilter.Category(rawValue: String($0).trimmingCharacters(in: .whitespaces))
        })
        return parsed.isEmpty ? Set(LocalNameFilter.Category.allCases) : parsed
    }

    var categoriesSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(LocalNameFilter.Category.allCases, id: \.self) { category in
                    categoryChip(category)
                }
            }
            .padding(.vertical, 4)
        } header: {
            SectionHelpHeader("Loại cần tìm", paragraphs: [
                "Chỉ giữ name thuộc các loại đang bật; phải bật ít nhất một loại. Lựa chọn được nhớ cho lần lọc sau.",
                "**Nhân danh**: tên người, cả tên kèm danh xưng (江镖头 → Giang tiêu đầu). **Địa danh**: tên chỗ (落霞镇 → Lạc Hà trấn). **Tổ chức**: tông môn, gia tộc, thương hội (圣元宫, 秦家). **Thuật ngữ**: công pháp, đan dược, pháp bảo (五气丹 → Ngũ Khí đan)."
            ])
        }
    }

    private func categoryChip(_ category: LocalNameFilter.Category) -> some View {
        let selected = selectedCategories
        let isOn = selected.contains(category)
        return Button {
            toggleCategory(category)
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(LocalNameFilterCategoryBadge.color(for: category))
                    .frame(width: 8, height: 8)
                Text(category.label)
                    .font(.subheadline)
                    .lineLimit(1)
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .foregroundColor(isOn ? .accentColor : .primary)
            .background(isOn ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.06))
            .clipShape(Capsule())
            .overlay(
                Capsule().stroke(isOn ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.14), lineWidth: 1)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityHint(isOn && selected.count == 1 ? "Phải bật ít nhất một loại" : "")
    }

    /// Bật / tắt một nhóm; nhóm cuối cùng đang bật thì giữ nguyên.
    private func toggleCategory(_ category: LocalNameFilter.Category) {
        var selected = selectedCategories
        if selected.contains(category) {
            guard selected.count > 1 else { return }
            selected.remove(category)
        } else {
            selected.insert(category)
        }
        categoriesRaw = LocalNameFilter.Category.allCases
            .filter { selected.contains($0) }
            .map(\.rawValue)
            .joined(separator: ",")
    }
}
