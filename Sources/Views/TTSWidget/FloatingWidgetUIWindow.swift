import SwiftUI
import UIKit

/// Overlay UIWindow có nền trong suốt, là ranh giới hit-testing duy nhất có thẩm quyền.
@MainActor
final class FloatingWidgetUIWindow: UIWindow {
    weak var containerViewController: FloatingWidgetContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Khi container đang hiển thị confirmationDialog, alert hoặc sheet, cho phép touch đầy đủ để tương tác dialog
        if containerViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }

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
