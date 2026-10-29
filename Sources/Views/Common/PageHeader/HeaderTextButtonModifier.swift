import SwiftUI

/// Chuẩn nút chữ trên header (1.3.652): Lưu, Nhập, Xong, Bắt đầu… — chữ 17pt nửa đậm, cùng nhịp với icon header
/// (`.system(size: 17, weight: .semibold)`) và nhỏ hơn tiêu đề trang 22pt.
///
/// - Áp lên chính `Button`/`Menu` trong `ToolbarItem`. Với `Menu("Lưu") { … }` chỉ nhãn đổi cỡ, các mục bên trong là menu hệ thống.
/// - Không đổi màu: nút xoá vẫn giữ màu đỏ của nó.
/// - Đừng gắn thêm `.fontWeight(...)`/`.bold()` lên `Text` của nhãn — chúng đè độ đậm của modifier này.
///
/// ```swift
/// ToolbarItem(placement: .confirmationAction) {
///     Button("Lưu") { save() }
///         .headerTextButton()
/// }
/// ```
struct HeaderTextButtonModifier: ViewModifier {
    static let fontSize: CGFloat = 17

    func body(content: Content) -> some View {
        content.font(.system(size: Self.fontSize, weight: .semibold))
    }
}

extension View {
    /// Nút chữ trên header: 17pt nửa đậm.
    func headerTextButton() -> some View {
        modifier(HeaderTextButtonModifier())
    }
}
