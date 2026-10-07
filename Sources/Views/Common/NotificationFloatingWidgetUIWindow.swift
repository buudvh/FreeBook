import UIKit

/// Overlay `UIWindow` nền trong suốt của widget thông báo nổi.
///
/// Là ranh giới hit-testing duy nhất có thẩm quyền: mọi điểm chạm **ngoài** vòng tròn 36px trả về `nil` để
/// rơi xuống cửa sổ bên dưới. Không có bước này thì một cửa sổ toàn màn hình sẽ nuốt mọi cú chạm của app —
/// cùng lý do đã ghi ở `BrowserFloatingWidgetUIWindow`.
///
/// Cửa sổ này **không bao giờ** gọi `makeKeyAndVisible()`: nó là lớp phủ thông tin, không phải cửa sổ chính.
@MainActor
final class NotificationFloatingWidgetUIWindow: UIWindow {
    weak var containerViewController: NotificationFloatingWidgetContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let widgetView = containerViewController?.widgetContainerView,
              !widgetView.isHidden,
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
