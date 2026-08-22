import SwiftUI
import UIKit

/// Overlay `UIWindow` nền trong suốt của widget trình duyệt thu nhỏ.
/// Là ranh giới hit-testing duy nhất có thẩm quyền: mọi điểm chạm ngoài viên pill
/// trả về `nil` để rơi xuống window bên dưới (app + TTS widget không bị chặn).
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
}
