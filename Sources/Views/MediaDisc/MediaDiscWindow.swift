import UIKit

/// Cửa sổ lớp phủ của đĩa nghe góc dưới phải (1.3.808), khuôn `FloatingWidgetUIWindow`: nền trong suốt, không bao giờ
/// key; chỉ khung đĩa nhận chạm, còn lại chạm xuyên xuống app. Container đang trình bày sheet điều khiển nhanh (hoặc sheet
/// chồng lên nó) ⇒ nhận chạm cả cửa sổ.
@MainActor
final class MediaDiscWindow: UIWindow, AppOverlayWindow {
    weak var containerViewController: MediaDiscContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let container = containerViewController else { return nil }
        if container.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }
        let disc = container.discView
        guard container.isDiscInteractive, !disc.isHidden else { return nil }
        let localPoint = disc.convert(point, from: self)
        guard disc.point(inside: localPoint, with: event) else { return nil }
        return super.hitTest(point, with: event)
    }
}
