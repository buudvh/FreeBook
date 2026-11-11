import UIKit

/// Cửa sổ của **sheet nằm trên mọi viên thuốc** (`OverlaySheetPresenter`, 2026-11-11): nền trong suốt, không bao giờ key;
/// không trình bày gì ⇒ mọi chạm xuyên xuống (và cửa sổ vốn ẩn lúc rảnh); đang trình bày sheet ⇒ nhận chạm cả cửa sổ
/// (luật 25 — sheet + lớp mờ của nó nằm trong chính cửa sổ này).
@MainActor
final class OverlaySheetWindow: UIWindow, AppOverlayWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard rootViewController?.presentedViewController != nil else { return nil }
        return super.hitTest(point, with: event)
    }
}
