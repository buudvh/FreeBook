import Foundation

/// Ba kiểu hiện tiêu đề trang của `PageTitleModifier` (1.3.652). Mọi kiểu đều giữ `.navigationTitle` thật.
enum PageTitleStyle {
    /// Tab gốc và gốc sheet: chữ 22pt đậm nằm **bên trái** thanh điều hướng, không co chữ.
    case leading
    /// Trang có nút trái (nút back, nút ‹ trang con trong sheet): chữ 22pt đậm ngay **cạnh nút trái** ở hàng nút (1.3.1018;
    /// 1.3.984–1.3.1017 là tiêu đề lớn hàng 2). Tên `centered` giữ từ thời tiêu đề nằm giữa (1.3.652) để khỏi đổi mọi chỗ
    /// gọi.
    case centered
    /// Không hiện tiêu đề nào (vd Chi tiết truyện — header là bìa lớn).
    case hidden
}
