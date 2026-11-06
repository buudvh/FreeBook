import UIKit

/// Hình học và chỗ đậu đã nhớ của cửa sổ phim nhỏ (1.3.751). Mọi khung tính theo toạ độ màn hình (cửa sổ phủ cả màn).
///
/// - Rộng 50% cạnh ngắn của màn, khung 16:9.
/// - **Bám mép trái/phải ở độ cao thả tay** (anh Bửu chọn): kẹp dưới thanh trạng thái và trên thanh tab tự vẽ.
/// - Chỗ đậu nhớ qua các lần mở app: `UserDefaults` khoá `videoMiniPlayerDock` (không dấu chấm), dạng `"right:0.78"` =
///   mép + tỉ lệ góc trên trong khoảng dọc cho phép. Chưa có ⇒ mép phải, sát dưới.
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
    private static let defaultsKey = "videoMiniPlayerDock"

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

    /// Chỗ đậu đã nhớ.
    static func dockFrame(in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let saved = savedDock()
        let size = size(in: bounds)
        let range = verticalRange(in: bounds, safeInsets: safeInsets, height: size.height)
        let originY = range.lowerBound + (range.upperBound - range.lowerBound) * saved.ratio
        return frame(edge: saved.edge, originY: originY, in: bounds, safeInsets: safeInsets)
    }

    /// Thả tay ở `frame` (đang hất theo `velocityX`) ⇒ mép gần nhất, giữ độ cao; ghi nhớ chỗ đậu mới.
    static func snap(_ frame: CGRect, velocityX: CGFloat, in bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let projectedMidX = frame.midX + velocityX * 0.15
        let edge: Edge = projectedMidX < bounds.midX ? .left : .right
        let snapped = self.frame(edge: edge, originY: frame.minY, in: bounds, safeInsets: safeInsets)
        let range = verticalRange(in: bounds, safeInsets: safeInsets, height: snapped.height)
        let span = range.upperBound - range.lowerBound
        let ratio = span > 0 ? (snapped.minY - range.lowerBound) / span : 1
        UserDefaults.standard.set("\(edge.rawValue):\(ratio)", forKey: defaultsKey)
        return snapped
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

    private static func savedDock() -> (edge: Edge, ratio: CGFloat) {
        guard let raw = UserDefaults.standard.string(forKey: defaultsKey) else { return (.right, 1) }
        let parts = raw.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let edge = Edge(rawValue: parts[0]), let ratio = Double(parts[1]) else { return (.right, 1) }
        return (edge, CGFloat(min(1, max(0, ratio))))
    }
}
