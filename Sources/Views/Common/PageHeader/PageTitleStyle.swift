import Foundation

/// Ba kiểu hiện tiêu đề trang của `PageTitleModifier` (1.3.652). Mọi kiểu đều giữ `.navigationTitle` thật.
enum PageTitleStyle {
    /// Tab gốc và gốc sheet: chữ 22pt đậm nằm **bên trái** thanh điều hướng, không co chữ.
    case leading
    /// Trang có nút back (1.3.984; cỡ 28pt từ 1.3.1017): chữ đậm ở **hàng 2**, sát lề trái, dưới hàng nút (tiêu đề lớn của iOS); cuộn lên
    /// thì thu lại, tiêu đề nhỏ 17pt hiện cạnh nút back. Tên `centered` giữ từ thời tiêu đề nằm giữa (1.3.652) để khỏi
    /// đổi mọi chỗ gọi.
    case centered
    /// Không hiện tiêu đề nào (vd Chi tiết truyện — header là bìa lớn).
    case hidden
}
