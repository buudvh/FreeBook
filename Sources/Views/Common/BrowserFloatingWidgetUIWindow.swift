import UIKit

/// Overlay `UIWindow` nền trong suốt của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533) — ranh giới
/// hit-testing duy nhất có thẩm quyền: mọi điểm chạm ngoài khung nửa viên của nút trả `nil` để rơi xuống cửa sổ bên
/// dưới (app, hub, đĩa nghe không bị chặn). Độ đậm "đang chạm" (mờ 0,7 khi nghỉ, bắt ở `sendEvent`) bỏ từ 2026-11-11:
/// icon nay mờ theo Độ trong suốt của nút nổi.
///
/// Cửa sổ này **không bao giờ** gọi `makeKeyAndVisible()`: nó là lớp phủ, không phải cửa sổ chính.
@MainActor
final class BrowserFloatingWidgetUIWindow: UIWindow, AppOverlayWindow {
    weak var containerViewController: BrowserFloatingWidgetContainerViewController?

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
