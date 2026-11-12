import UIKit

/// Cửa sổ của **sheet nằm trên mọi viên thuốc** (`OverlaySheetPresenter`, 2026-11-11): nền trong suốt, chỉ hiện + nhận key
/// trong lúc có sheet (1.3.872, để trang con có ô nhập gõ được); không trình bày gì ⇒ mọi chạm xuyên xuống (và cửa sổ vốn
/// ẩn lúc rảnh); đang trình bày sheet ⇒ nhận chạm cả cửa sổ (luật 25 — sheet + lớp mờ của nó nằm trong chính cửa sổ này).
@MainActor
final class OverlaySheetWindow: UIWindow, AppOverlayWindow {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard rootViewController?.presentedViewController != nil else { return nil }
        return super.hitTest(point, with: event)
    }
}
