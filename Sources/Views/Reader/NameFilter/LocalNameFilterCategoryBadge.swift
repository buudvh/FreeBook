import SwiftUI

/// Badge loại của một name trong luồng "Lọc name local" (mockup LAC khung 2–3): nền màu theo nhóm, chữ đen — Nhân danh
/// xanh dương, Địa danh xanh lá, Tổ chức cam, Thuật ngữ tím. Màu nằm **một chỗ** (`color(for:)`), dùng chung cho chấm
/// màu của chip "Loại cần tìm" (sheet thiết lập), hàng hiện dần ở màn đang lọc và thẻ duyệt.
///
/// Nhãn không thuộc bốn nhóm (name thêm bằng màn Sửa từ ở màn duyệt, `AINameEdit.addedCategory`…) ⇒ badge xám như cũ.
/// Luồng AI **không** dùng view này: nhãn AI có thể trùng chữ ("Địa danh") mà vẫn giữ badge xám.
struct LocalNameFilterCategoryBadge: View {
    let label: String

    var body: some View {
        let category = Self.category(forLabel: label)
        Text(label)
            .font(.system(size: 9, weight: category == nil ? .semibold : .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(category.map(Self.color(for:)) ?? Color(white: 0.25))
            .foregroundColor(category == nil ? .white : .black)
            .cornerRadius(4)
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Màu của nhóm (bảng màu hệ thống tối của iOS, như mockup).
    static func color(for category: LocalNameFilter.Category) -> Color {
        switch category {
        case .person: return Color(red: 90 / 255, green: 170 / 255, blue: 255 / 255)
        case .place: return Color(red: 48 / 255, green: 209 / 255, blue: 88 / 255)
        case .organization: return Color(red: 255 / 255, green: 159 / 255, blue: 10 / 255)
        case .term: return Color(red: 191 / 255, green: 90 / 255, blue: 242 / 255)
        }
    }

    /// Nhóm có nhãn đúng bằng `label` (`LocalNameFilter.Category.label`); `nil` = nhãn khác.
    static func category(forLabel label: String) -> LocalNameFilter.Category? {
        LocalNameFilter.Category.allCases.first { $0.label == label }
    }
}
