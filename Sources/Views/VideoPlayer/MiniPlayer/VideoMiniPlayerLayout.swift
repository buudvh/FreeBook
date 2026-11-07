import UIKit

/// Hình học của cửa sổ phim nhỏ (1.3.751). Mọi khung tính theo toạ độ màn hình (cửa sổ phủ cả màn).
///
/// - Rộng 50% cạnh ngắn của màn, khung 16:9.
/// - Mỗi lần thu nhỏ đều đậu ở **góc dưới phải, ngay trên thanh tab** (1.3.765, anh Bửu chọn — không nhớ chỗ cũ; khoá
///   `videoMiniPlayerDock` của 1.3.751 bỏ không đọc nữa).
/// - Đang hiện thì kéo **bám mép trái/phải ở độ cao thả tay**, kẹp dưới thanh trạng thái và trên thanh tab; không ghi lại.
/// - Thả lên nút hub (`isOverHub`) ⇒ thu vào hub; thả vào vòng ✕ ở đáy ⇒ tắt.
enum VideoMiniPlayerLayout {
    enum Edge: String {
        case left
        case right
    }

    /// Bo góc cửa sổ — khung phim đang co (`VideoMinimizeDragContainer`) tới nơi cũng đúng góc này.
    static let cornerRadius: CGFloat = 10
    static let horizontalMargin: CGFloat = 8
    static let topMargin: CGFloat = 8
    /// Chừa thanh tab tự vẽ (`MainTabBar`) ở dưới.
    static let bottomReserve: CGFloat = 64
    static let closeTargetSize: CGFloat = 60
    static let closeTargetBottomGap: CGFloat = 24
    /// Tâm cửa sổ cách tâm vòng ✕ trong khoảng này ⇒ thả là tắt.
    static let closeHitRadius: CGFloat = 70
    /// Tâm cửa sổ cách tâm nút hub trong khoảng này ⇒ thả là thu vào hub. Cửa sổ đang đậu ở mép phải ngang hub (tâm cách
    /// ~100 pt) không tự lọt vào — phải đẩy thêm về phía hub.
    static let hubHitRadius: CGFloat = 60

    static func size(in bounds: CGRect) -> CGSize {
        let width = (min(bounds.width, bounds.height) * 0.5).rounded()
        return CGSize(width: width, height: (width * 9 / 16).rounded())
    }

    /// Khoảng cho phép của góc trên cửa sổ.
    static func verticalRange(in bounds: CGRect, safeInsets: UIEdgeInsets, height: CGFloat) -> ClosedRange<CGFloat> {
        let minY = safeInsets.top + topMargin
        let maxY = max(minY, bounds.height - safeInsets.bottom - bottomReserve - height)
        return minY...maxY
    }

    static func frame(edge: Edge, originY: CGFloat, in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let size = size(in: bounds)
        let range = verticalRange(in: bounds, safeInsets: safeInsets, height: size.height)
        let y = min(max(originY, range.lowerBound), range.upperBound)
        let x = edge == .left ? horizontalMargin : bounds.width - horizontalMargin - size.width
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Chỗ đậu mỗi lần thu nhỏ: góc dưới phải, ngay trên thanh tab.
    static func dockFrame(in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let size = size(in: bounds)
        let range = verticalRange(in: bounds, safeInsets: safeInsets, height: size.height)
        return frame(edge: .right, originY: range.upperBound, in: bounds, safeInsets: safeInsets)
    }

    /// Thả tay ở `frame` (đang hất theo `velocityX`) ⇒ mép gần nhất, giữ độ cao. Không ghi nhớ.
    static func snap(_ frame: CGRect, velocityX: CGFloat, in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let projectedMidX = frame.midX + velocityX * 0.15
        let edge: Edge = projectedMidX < bounds.midX ? .left : .right
        return self.frame(edge: edge, originY: frame.minY, in: bounds, safeInsets: safeInsets)
    }

    /// Cửa sổ đang kéo nằm trên nút hub (`hubFrame` = khung nút hub, `nil` khi hub ẩn).
    static func isOverHub(_ frame: CGRect, hubFrame: CGRect?) -> Bool {
        guard let hubFrame else { return false }
        return hypot(frame.midX - hubFrame.midX, frame.midY - hubFrame.midY) < hubHitRadius
    }

    /// Mép gần nhất của một khung đang kéo — để làm sáng vạch mép.
    static func nearestEdge(of frame: CGRect, in bounds: CGRect) -> Edge {
        frame.midX < bounds.midX ? .left : .right
    }

    static func closeTargetFrame(in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let side = closeTargetSize
        return CGRect(
            x: bounds.midX - side / 2,
            y: bounds.height - safeInsets.bottom - closeTargetBottomGap - side,
            width: side,
            height: side
        )
    }

    static func isOverCloseTarget(_ frame: CGRect, in bounds: CGRect, safeInsets: UIEdgeInsets) -> Bool {
        let target = closeTargetFrame(in: bounds, safeInsets: safeInsets)
        return hypot(frame.midX - target.midX, frame.midY - target.midY) < closeHitRadius
    }

    /// Khung phim của màn xem (16:9, sát dưới thanh trạng thái) — đích khi cửa sổ nhỏ nở lại.
    static func expandedVideoFrame(in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        CGRect(x: 0, y: safeInsets.top, width: bounds.width, height: (bounds.width * 9 / 16).rounded())
    }
}
