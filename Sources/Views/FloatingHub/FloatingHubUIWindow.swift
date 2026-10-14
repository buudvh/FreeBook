import UIKit

/// Overlay `UIWindow` nền trong suốt của nút hub nổi (1.3.524) — ranh giới hit-testing duy nhất có thẩm quyền.
///
/// Thứ tự ba nhánh dưới đây là **bắt buộc**:
/// 1. Container đang trình bày sheet màn Thông báo ⇒ touch đi đủ đường (luật 25, `rules.md`).
/// 2. Menu đang mở và nút đang hiện ⇒ touch đi đủ đường: lớp nền trong suốt toàn màn nhận chạm ngoài thẻ để
///    đóng menu. Đây là lúc duy nhất cửa sổ nuốt chạm của app, nên cờ menu phải được hạ ở mọi đường (xem
///    `FloatingHubViewModel.isMenuOpen`).
/// 3. Còn lại: chỉ nhận chạm trong vòng tròn của nút; ngoài đó trả `nil` để rơi xuống cửa sổ bên dưới.
///
/// Cửa sổ này **không bao giờ** gọi `makeKeyAndVisible()`: nó là lớp phủ, không phải cửa sổ chính.
@MainActor
final class FloatingHubUIWindow: UIWindow {
    weak var containerViewController: FloatingHubContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let container = containerViewController else { return nil }

        // (1) Sheet màn Thông báo được trình bày từ chính cửa sổ này nên view của nó nằm trong cây của cửa
        // sổ, mà lúc đó `widgetContainerView` lại bị `isHidden = true` (xem `setSheetPresented`). Thiếu nhánh
        // này, guard bên dưới thất bại ⇒ mọi cú chạm trên sheet rơi xuống app phía dưới: không bấm được "Đóng".
        if container.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }

        let widgetView = container.widgetContainerView

        // (2) Menu mở: thẻ menu, nút hub và lớp nền đều nằm trong cây của cửa sổ — `super` chọn đúng view.
        if container.isMenuOpen && !widgetView.isHidden {
            return super.hitTest(point, with: event)
        }

        // (3) Chỉ vòng tròn của nút.
        guard !widgetView.isHidden,
              widgetView.alpha > 0.01,
              widgetView.isUserInteractionEnabled else {
            return nil
        }

        let localPoint = widgetView.convert(point, from: self)
        guard widgetView.point(inside: localPoint, with: event) else {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}
