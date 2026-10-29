import Foundation

/// Ba kiểu hiện tiêu đề trang của `PageTitleModifier` (1.3.652). Mọi kiểu đều giữ `.navigationTitle` thật.
enum PageTitleStyle {
    /// Tab gốc và gốc sheet: chữ 22pt đậm nằm **bên trái** thanh điều hướng.
    case leading
    /// Trang có nút back: chữ 22pt đậm nằm **giữa** thanh điều hướng (ô `principal`).
    case centered
    /// Không hiện tiêu đề nào (vd Chi tiết truyện — header là bìa lớn).
    case hidden
}
