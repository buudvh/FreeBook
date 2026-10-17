import UIKit

/// Overlay `UIWindow` nền trong suốt của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533) — ranh giới
/// hit-testing duy nhất có thẩm quyền: mọi điểm chạm ngoài vòng tròn của nút trả `nil` để rơi xuống cửa sổ bên
/// dưới (app, hub, widget TTS không bị chặn).
///
/// ## Bắt "đang chạm" ở `sendEvent`
/// `UITapGestureRecognizer` chỉ báo lúc nhấc tay, nên độ đậm "đang chạm" (alpha 1,0 thay vì 0,7) lấy từ chính
/// luồng sự kiện: cửa sổ này **chỉ** nhận chạm trên nút (`hitTest` trả `nil` ở mọi chỗ khác), nên còn ngón
/// nào chưa `.ended`/`.cancelled` là đang chạm hoặc đang kéo. Không thêm gesture recognizer nào chen vào bảng
/// chạm/kéo của container.
///
/// Cửa sổ này **không bao giờ** gọi `makeKeyAndVisible()`: nó là lớp phủ, không phải cửa sổ chính.
@MainActor
final class BrowserFloatingWidgetUIWindow: UIWindow {
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

    override func sendEvent(_ event: UIEvent) {
        if event.type == .touches, let touches = event.allTouches {
            let ownTouches = touches.filter { $0.window === self }
            if !ownTouches.isEmpty {
                // Chỉ ba pha của ngón tay đang đặt trên màn; pha `region*` (con trỏ iPad lướt qua) không tính.
                let isTouching = ownTouches.contains { touch in
                    touch.phase == .began || touch.phase == .moved || touch.phase == .stationary
                }
                containerViewController?.setTouchActive(isTouching)
            }
        }
        super.sendEvent(event)
    }
}
