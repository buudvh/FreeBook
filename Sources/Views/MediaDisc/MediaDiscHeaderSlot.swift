import UIKit

/// Chỗ của đĩa góc khi **nhấn giữ** (1.3.815, anh Bửu duyệt mockup): đĩa nằm **trong header** như một nút header — bìa
/// 32 pt canh giữa hàng nút, đứng ngay trái cụm nút bên phải, không đè nút nào, không tràn xuống dưới header.
///
/// Dò trên **tầng trình bày trên cùng** của cửa sổ chính (`MediaDiscPlacement.topLayer`), theo thứ tự:
/// 1. Neo `.headerTrailing` hợp lệ (header tự dựng: Reader, màn truyện tranh) ⇒ trái neo 6 pt (khe nút của hai header đó).
/// 2. `UINavigationBar` đang hiện (trang đẩy vào, Chi tiết, sheet, trình duyệt) ⇒ mép trái nhỏ nhất của các view nút nằm
///    hẳn ở nửa phải thanh ⇒ trái đó 2 pt (`HeaderButtonMetrics.pairSpacing`); thanh không có nút phải ⇒ lề phải 16 pt.
///    Chỉ đọc khung + cờ hiện của view, **không** dựa tên lớp riêng của iOS; nền / vùng nội dung của thanh (rộng) và nút
///    quay lại / tiêu đề (chạm nửa trái) tự bị loại.
/// 3. Không dò được ⇒ góc phải vùng header: lề phải 16 pt, giữa dải 44 pt ngay dưới thanh trạng thái.
@MainActor
enum MediaDiscHeaderSlot {
    enum Source: String {
        case customHeader = "header tự dựng"
        case navigationBar = "thanh điều hướng"
        case fallback = "góc phải vùng header"
    }

    /// Bìa đĩa trong header = bìa của đĩa góc.
    static let coverSize: CGFloat = 32

    private static let customHeaderSpacing: CGFloat = 6
    private static let headerHeight: CGFloat = 44
    /// Rộng hơn mức này thì không phải một nút / cụm nút (nền, vùng nội dung của thanh).
    private static let maxButtonWidth: CGFloat = 160

    /// Tâm đĩa (toạ độ cửa sổ — mọi cửa sổ của app phủ cả scene) + nguồn đã dùng.
    static func resolve(bounds: CGRect, safeInsets: UIEdgeInsets) -> (center: CGPoint, source: Source) {
        let fallback = CGPoint(
            x: bounds.width - safeInsets.right - FloatingRoundButton.trailingInset - coverSize / 2,
            y: safeInsets.top + headerHeight / 2
        )
        guard let window = MediaDiscPlacement.mainWindow() else { return (fallback, .fallback) }
        let top = MediaDiscPlacement.topLayer(of: window)

        let trailingAnchors = MediaDiscAnchorRegistry.shared.anchors
            .filter { $0.role == .headerTrailing }
            .compactMap { MediaDiscPlacement.validFrame(of: $0.view, in: window, top: top) }
        if let cluster = trailingAnchors.min(by: { $0.minY < $1.minY }) {
            return (CGPoint(x: cluster.minX - customHeaderSpacing - coverSize / 2, y: cluster.midY), .customHeader)
        }

        if let rootView = top?.view, let bar = visibleNavigationBar(in: rootView, window: window) {
            let barFrame = bar.convert(bar.bounds, to: nil)
            let trailingEdge = trailingButtonsMinX(in: bar, barFrame: barFrame)
                ?? (barFrame.maxX - safeInsets.right - FloatingRoundButton.trailingInset + HeaderButtonMetrics.pairSpacing)
            let center = CGPoint(
                x: trailingEdge - HeaderButtonMetrics.pairSpacing - coverSize / 2,
                y: barFrame.minY + min(barFrame.height, headerHeight) / 2
            )
            return (center, .navigationBar)
        }
        return (fallback, .fallback)
    }

    // MARK: - Thanh điều hướng

    /// Thanh điều hướng đầu tiên đang thật sự hiện (không ẩn, nằm trong màn) trong cây view của tầng trên cùng.
    private static func visibleNavigationBar(in root: UIView, window: UIWindow) -> UINavigationBar? {
        var queue: [UIView] = [root]
        var index = 0
        while index < queue.count {
            let view = queue[index]
            index += 1
            guard !view.isHidden, view.alpha > 0.01 else { continue }
            if let bar = view as? UINavigationBar {
                let frame = bar.convert(bar.bounds, to: nil)
                if bar.window === window, frame.height > 0,
                   frame.minX >= window.bounds.minX - 1, frame.maxX <= window.bounds.maxX + 1 {
                    return bar
                }
                continue
            }
            queue.append(contentsOf: view.subviews)
        }
        return nil
    }

    /// Mép trái (toạ độ cửa sổ) của cụm nút bên phải thanh; không có nút ⇒ `nil`.
    private static func trailingButtonsMinX(in bar: UINavigationBar, barFrame: CGRect) -> CGFloat? {
        var minX: CGFloat?
        var stack: [UIView] = bar.subviews
        while let view = stack.popLast() {
            guard !view.isHidden, view.alpha > 0.01 else { continue }
            stack.append(contentsOf: view.subviews)
            let frame = view.convert(view.bounds, to: nil)
            guard frame.width > 4, frame.width <= maxButtonWidth, frame.height > 4,
                  frame.minX > barFrame.midX, frame.maxX <= barFrame.maxX + 1,
                  frame.midY >= barFrame.minY, frame.midY <= barFrame.maxY else { continue }
            minX = min(minX ?? frame.minX, frame.minX)
        }
        return minX
    }
}
