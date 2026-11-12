import UIKit

/// Chỗ đứng của đĩa nghe — **nửa viên thuốc dính mép** (anh Bửu duyệt mockup 2026-11-11, thay đĩa tròn góc dưới phải của
/// 1.3.808), tính lại mỗi lượt từ chỗ người dùng kéo tới (`MediaDiscPositionStore`) và cây UIKit của **cửa sổ chính** — đĩa
/// sống ở cửa sổ riêng nhưng mọi cửa sổ của app đều phủ cả scene nên toạ độ cửa sổ chính dùng thẳng được.
///
/// ## Luật
/// 1. **Tầng trên cùng** = VC được trình bày sâu nhất của cửa sổ chính, bỏ qua VC đang bị đóng. Là hộp thoại / bảng chọn
///    (`UIAlertController`, kể cả `confirmationDialog`) hay bảng chia sẻ ⇒ **ẩn** đĩa.
/// 2. Một neo (`MediaDiscAnchorRegistry`) chỉ được tính khi: nằm trong cửa sổ chính, VC gốc tầng của nó **chính là** tầng
///    trên cùng, và khung nằm trong màn. Không xét `isHidden` / alpha: neo có điều kiện tự biến mất khỏi cây.
/// 3. Có neo `.blocker` hợp lệ (màn xem phim) ⇒ ẩn. (Neo `.hostsDisc` của ô đĩa giữa thanh tab
///    bỏ ở 1.3.865: thanh tab nay là neo `.bar`.)
/// 4. Đĩa ở mép + độ cao đã nhớ, kẹp trong **vùng đứng cố định** `EdgePillZone` (1.3.867, anh Bửu: "tránh header và thanh
///    tab dù có hay không, tránh nó chạy lên chạy xuống"): dưới vùng header, trên vùng nút "+" / thanh tab — kể cả màn
///    không có chúng. Chưa kéo lần nào ⇒ mép phải, thấp nhất của vùng (ngay trên chỗ nút "+").
/// 5. Chỉ neo / cửa sổ phim nhỏ **lấn vào vùng** (mép trên cao hơn đáy vùng — cụm pill của menu "+" đang xổ, cửa sổ phim
///    nhỏ được kéo lên) mà chồng cột với đĩa (kể khe 12 pt) mới **tạm đẩy** đĩa lên trên nó. Nút "+", Home, tai nghe Reader,
///    thanh tab, thanh dưới trình duyệt / truyện tranh nằm dưới vùng ⇒ không bao giờ đẩy ⇒ đĩa không nhảy khi đổi màn.
///    Chỉ dời lúc vẽ, không ghi đè chỗ đã nhớ.
struct MediaDiscPlacement: Equatable {
    /// Cao của đĩa (= nút "+") — cũng là đường kính lúc đang kéo.
    static let discSize: CGFloat = 52
    /// Cỡ nửa viên lúc dính mép — độ nhô đọc lúc chạy (Giao diện › Viên thuốc nổi, `EdgePillSettings`).
    static var pillSize: CGSize { EdgePillSettings.size(of: .disc) }
    /// Bìa trong đĩa (như icon của nút "+").
    static let coverSize: CGFloat = 32
    /// Khe giữa đĩa và neo lấn vào vùng.
    static let gap: CGFloat = 12

    /// Khung đĩa theo toạ độ cửa sổ.
    let frame: CGRect
    let edge: EdgeDirection
    /// Màn trên cùng không cho hiện đĩa.
    let isBlocked: Bool

    /// Dải mép trên của nửa viên được phép (`EdgePillZone`, trước khi né neo lấn vào vùng).
    static func topRange(bounds: CGRect, safeInsets: UIEdgeInsets) -> ClosedRange<CGFloat> {
        EdgePillZone.topRange(height: pillSize.height, bounds: bounds, safeInsets: safeInsets)
    }

    /// Khung nửa viên dính mép `edge`, mép trên `top`.
    static func dockedFrame(edge: EdgeDirection, top: CGFloat, bounds: CGRect) -> CGRect {
        let size = pillSize
        let x = edge == .left ? bounds.minX : bounds.maxX - size.width
        return CGRect(x: x, y: top, width: size.width, height: size.height)
    }

    /// Đọc chỗ đĩa cho màn `bounds` (vùng an toàn `safeInsets`) của cửa sổ đĩa.
    @MainActor
    static func resolve(
        bounds: CGRect,
        safeInsets: UIEdgeInsets,
        position: MediaDiscPositionStore.Position
    ) -> MediaDiscPlacement {
        let range = topRange(bounds: bounds, safeInsets: safeInsets)
        let wantedTop: CGFloat
        if let ratio = position.verticalRatio {
            wantedTop = ratio * bounds.height - pillSize.height / 2
        } else {
            wantedTop = range.upperBound
        }
        let top = min(max(wantedTop, range.lowerBound), range.upperBound)
        var frame = dockedFrame(edge: position.edge, top: top, bounds: bounds)

        guard let mainWindow = mainWindow() else {
            return MediaDiscPlacement(frame: frame, edge: position.edge, isBlocked: false)
        }
        let topVC = topLayer(of: mainWindow)
        if topVC is UIAlertController || topVC is UIActivityViewController {
            return MediaDiscPlacement(frame: frame, edge: position.edge, isBlocked: true)
        }

        // Chỉ thứ lấn vào vùng đứng (mép trên cao hơn đáy vùng) mới phải né — xem luật 5.
        let zoneBottom = EdgePillZone.maxBottom(bounds: bounds, safeInsets: safeInsets)
        var obstacles: [CGRect] = []
        for anchor in MediaDiscAnchorRegistry.shared.anchors {
            guard let rect = validFrame(of: anchor.view, in: mainWindow, top: topVC) else { continue }
            switch anchor.role {
            case .blocker:
                return MediaDiscPlacement(frame: frame, edge: position.edge, isBlocked: true)
            case .button, .bar:
                if rect.minY < zoneBottom { obstacles.append(rect) }
            }
        }
        if let mini = VideoMiniPlayerWindowManager.shared.visiblePlayerFrame, mini.minY < zoneBottom {
            obstacles.append(mini)
        }
        frame.origin.y = liftedTop(of: frame, above: obstacles, minTop: range.lowerBound)
        return MediaDiscPlacement(frame: frame, edge: position.edge, isBlocked: false)
    }

    // MARK: - Nội bộ

    /// Đẩy đĩa lên trên mọi vật cản chồng cột mà nó đè (kể khe), lặp tới khi hết đè; không xuống dưới `minTop`.
    private static func liftedTop(of frame: CGRect, above obstacles: [CGRect], minTop: CGFloat) -> CGFloat {
        let column = obstacles.filter { $0.maxX > frame.minX && $0.minX < frame.maxX }
        var top = frame.minY
        for _ in 0..<8 {
            let span = top...(top + frame.height)
            guard let hit = column.first(where: { $0.minY - gap < span.upperBound && $0.maxY + gap > span.lowerBound })
            else { break }
            top = hit.minY - gap - frame.height
        }
        return max(top, minTop)
    }

    /// Cửa sổ giao diện chính của app (level `.normal`, không phải lớp phủ), ưu tiên cửa sổ key.
    @MainActor
    static func mainWindow() -> UIWindow? {
        guard let scene = AppMainWindowScene.current() else { return nil }
        let candidates = scene.windows.filter { !($0 is AppOverlayWindow) && $0.windowLevel == .normal && !$0.isHidden }
        return candidates.first { $0.isKeyWindow } ?? candidates.first
    }

    /// VC trình bày sâu nhất (bỏ qua VC đang bị đóng); không có gì trình bày ⇒ root.
    @MainActor
    static func topLayer(of window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Khung neo theo toạ độ cửa sổ nếu neo hợp lệ (đúng cửa sổ, đúng tầng trên cùng, nằm trong màn).
    @MainActor
    static func validFrame(of view: UIView, in window: UIWindow, top: UIViewController?) -> CGRect? {
        guard view.window === window, let top, layerRoot(of: view) === top else { return nil }
        let rect = view.convert(view.bounds, to: nil)
        let screen = window.bounds
        guard rect.midX >= screen.minX, rect.midX <= screen.maxX,
              rect.maxY > screen.minY, rect.minY < screen.maxY else { return nil }
        return rect
    }

    /// VC gốc của tầng chứa `view`: VC gần nhất (theo responder) rồi đi `parent` tới cùng.
    @MainActor
    private static func layerRoot(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder, !(current is UIViewController) {
            responder = current.next
        }
        guard var controller = responder as? UIViewController else { return nil }
        while let parent = controller.parent {
            controller = parent
        }
        return controller
    }
}
