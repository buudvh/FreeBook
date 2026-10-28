import UIKit

/// Cửa sổ nổi của ngăn kéo menu (`SideDrawerMenuWindowManager`).
///
/// Khi ngăn kéo đang mở, lớp phủ tối + ngăn kéo phủ kín màn nên cửa sổ nhận mọi cú chạm. Từ lúc bắt đầu đóng
/// (`isUserInteractionEnabled = false`) hoặc khi đã ẩn, `hitTest` trả `nil` để chạm rơi thẳng xuống cửa sổ bên dưới —
/// không bao giờ còn một lớp vô hình chặn chạm của app.
///
/// Không bao giờ gọi `makeKeyAndVisible()`: đây là lớp phủ, không phải cửa sổ chính.
final class SideDrawerMenuOverlayWindow: UIWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden else { return nil }
        return super.hitTest(point, with: event)
    }
}
