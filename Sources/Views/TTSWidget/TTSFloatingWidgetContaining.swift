import UIKit

/// Root view controller của cửa sổ widget TTS (`FloatingWidgetUIWindow`), 1.3.796: kiểu Đĩa nổi
/// (`FloatingWidgetContainerViewController`) hoặc Thanh nghe nhạc (`TTSWidgetBarContainerViewController`).
///
/// `widgetContainerView` là vùng **duy nhất** nhận chạm — cửa sổ hit-test theo khung của nó, phần còn lại chạm xuyên
/// xuống app (trừ khi container đang trình bày sheet/dialog).
@MainActor
protocol TTSFloatingWidgetContaining: UIViewController {
    var widgetContainerView: UIView { get }

    /// Widget vừa chuyển từ ẩn sang hiện: lượt layout kế tiếp xếp lại chỗ (né widget nổi khác) nếu kiểu đó có xếp.
    func requestPlacementResolve()

    /// Mở rộng widget (viên điều khiển của Đĩa nổi / bung thanh).
    func reveal(animated: Bool)

    func updateLayoutForCurrentMode(animated: Bool)
}
