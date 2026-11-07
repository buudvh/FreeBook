import SwiftUI

/// Một pill của menu xổ nút nổi (`FloatingActionMenu`): chữ + icon trên nền kính dạng viên thuốc. `highlight` = trạng
/// thái đang bật (vd "Đã ở kệ"): viền và icon theo màu này thay cho nền đặc (nền luôn là kính theo Cài đặt › Giao diện).
struct FloatingActionItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    var highlight: Color?
    let action: @MainActor () -> Void

    init(
        id: String,
        title: String,
        systemImage: String,
        highlight: Color? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.highlight = highlight
        self.action = action
    }

    /// Chữ / nhãn trợ năng của nút Home nổi (nút tròn riêng và pill).
    static let homeTitle = "Về trang gốc"

    /// Pill "Về trang gốc" của nút Home nổi — người gọi đặt nó **cuối** danh sách (pill dưới cùng, sát nút tròn).
    static func home(_ action: @escaping @MainActor () -> Void) -> FloatingActionItem {
        FloatingActionItem(id: "floating-home", title: homeTitle, systemImage: "house", action: action)
    }
}
