import UIKit

/// Overlay `UIWindow` nền trong suốt của nút hub nổi (1.3.524) — ranh giới hit-testing duy nhất có thẩm quyền.
///
/// Thứ tự hai nhánh dưới đây là **bắt buộc**:
/// 1. Container đang trình bày sheet (sheet hub, màn Thông báo) ⇒ touch đi đủ đường (luật 25, `rules.md`).
/// 2. Còn lại: chỉ nhận chạm trong khung nửa viên của nút; ngoài đó trả `nil` để rơi xuống cửa sổ bên dưới.
/// Thẻ menu nổi + lớp nền nuốt chạm toàn màn (nhánh "menu đang mở") bỏ từ 2026-11-11 khi menu thành sheet.
///
/// Cửa sổ này **không bao giờ** gọi `makeKeyAndVisible()`: nó là lớp phủ, không phải cửa sổ chính.
@MainActor
final class FloatingHubUIWindow: UIWindow, AppOverlayWindow {
    weak var containerViewController: FloatingHubContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let container = containerViewController else { return nil }

        // (1) Sheet hub / màn Thông báo được trình bày từ chính cửa sổ này nên view của nó nằm trong cây của cửa
        // sổ, mà lúc đó `widgetContainerView` lại bị `isHidden = true` (xem `setSheetPresented`). Thiếu nhánh
        // này, guard bên dưới thất bại ⇒ mọi cú chạm trên sheet rơi xuống app phía dưới.
        if container.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }

        let widgetView = container.widgetContainerView

        // (2) Chỉ khung nửa viên của nút.
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
