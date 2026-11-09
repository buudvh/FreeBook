import UIKit

/// Chỗ đứng của đĩa nghe góc dưới phải (1.3.808), tính lại mỗi lượt từ cây UIKit của **cửa sổ chính** — đĩa sống ở cửa sổ
/// riêng nhưng mọi cửa sổ của app đều phủ cả scene nên toạ độ cửa sổ chính dùng thẳng được (như
/// `FloatingWidgetLayoutCoordinator`).
///
/// ## Luật
/// 1. **Tầng trên cùng** = VC được trình bày sâu nhất của cửa sổ chính, bỏ qua VC đang bị đóng. Là hộp thoại / bảng chọn
///    (`UIAlertController`, kể cả `confirmationDialog`) hay bảng chia sẻ ⇒ **ẩn** đĩa (chúng mọc từ đáy, đĩa sẽ che nút).
/// 2. Một neo (`MediaDiscAnchorRegistry`) chỉ được tính khi: nằm trong cửa sổ chính, VC gốc tầng của nó **chính là** tầng
///    trên cùng (neo trong sheet thắng neo của trang dưới sheet), và khung nằm trong màn (trang bên cạnh của `TabView`
///    dạng trang, trang đang trượt ra ngoài thì không). Không xét `isHidden` / alpha: SwiftUI `.opacity` không chắc chạm tới
///    view của đầu dò — neo có điều kiện tự biến mất khỏi cây.
/// 3. Có neo `.blocker` hợp lệ (màn xem phim) hoặc `.hostsDisc` (thanh tab tự có ô đĩa, 1.3.812) ⇒ ẩn.
/// 4. Trong các neo `.button` / `.bar` hợp lệ lấy neo **cao nhất** (mép trên nhỏ nhất): trang gốc Kệ Sách có cả nút "+" lẫn
///    thanh tab ⇒ đĩa trên nút "+"; Lịch Sử chỉ có thanh tab ⇒ đĩa trên thanh tab; menu "+" đang xổ ⇒ đĩa trên cụm pill.
///    Mép dưới đĩa = mép trên neo − 12 pt. Mép phải: neo `.button` ⇒ trùng mép phải neo (nút tai nghe Reader lề 12 pt vẫn
///    thẳng cột); neo `.bar` ⇒ lề phải 16 pt.
/// 5. Không neo nào ⇒ góc dưới phải: lề phải 16 pt, trên vùng an toàn đáy 12 pt (chỗ nút "+" thường đứng).
/// 6. Cửa sổ phim nhỏ (`VideoMiniPlayerWindowManager`) đè lên chỗ đó ⇒ đĩa lên trên nó.
///
/// `elevatedFrame` = chỗ tạm khi nhấn giữ đĩa (1.3.812): góc phải vùng header, mép trên ngay dưới thanh trạng thái.
struct MediaDiscPlacement: Equatable {
    static let discSize: CGFloat = 52
    /// Khe giữa đĩa và neo bên dưới.
    static let gap: CGFloat = 12

    /// Khung đĩa theo toạ độ cửa sổ.
    let frame: CGRect
    /// Màn trên cùng không cho hiện đĩa.
    let isBlocked: Bool

    /// Đọc chỗ đĩa cho màn `bounds` (vùng an toàn `safeInsets`) của cửa sổ đĩa.
    @MainActor
    static func resolve(bounds: CGRect, safeInsets: UIEdgeInsets) -> MediaDiscPlacement {
        var bottom = bounds.height - safeInsets.bottom - FloatingRoundButton.bottomInset
        var trailing = bounds.width - safeInsets.right - FloatingRoundButton.trailingInset
        let corner = discFrame(trailing: trailing, bottom: bottom, bounds: bounds, safeInsets: safeInsets)

        guard let mainWindow = mainWindow() else {
            return MediaDiscPlacement(frame: corner, isBlocked: false)
        }
        let top = topLayer(of: mainWindow)
        if top is UIAlertController || top is UIActivityViewController {
            return MediaDiscPlacement(frame: corner, isBlocked: true)
        }

        var highest: (rect: CGRect, role: MediaDiscAnchorRegistry.Role)?
        for anchor in MediaDiscAnchorRegistry.shared.anchors {
            guard let rect = validFrame(of: anchor.view, in: mainWindow, top: top) else { continue }
            if anchor.role == .blocker || anchor.role == .hostsDisc {
                return MediaDiscPlacement(frame: corner, isBlocked: true)
            }
            if let current = highest, rect.minY >= current.rect.minY { continue }
            highest = (rect, anchor.role)
        }
        if let highest {
            bottom = highest.rect.minY - gap
            if highest.role == .button {
                trailing = highest.rect.maxX
            }
        }

        var result = discFrame(trailing: trailing, bottom: bottom, bounds: bounds, safeInsets: safeInsets)
        if let mini = VideoMiniPlayerWindowManager.shared.visiblePlayerFrame,
           result.insetBy(dx: -gap / 2, dy: -gap / 2).intersects(mini) {
            result = discFrame(trailing: trailing, bottom: mini.minY - gap, bounds: bounds, safeInsets: safeInsets)
        }
        return MediaDiscPlacement(frame: result, isBlocked: false)
    }

    /// Chỗ tạm ở góc phải vùng header (nhấn giữ đĩa): lề phải 16 pt như nút header, mép trên ngay dưới thanh trạng thái.
    @MainActor
    static func elevatedFrame(bounds: CGRect, safeInsets: UIEdgeInsets) -> CGRect {
        let x = bounds.width - safeInsets.right - FloatingRoundButton.trailingInset - discSize
        return CGRect(x: max(safeInsets.left, x), y: safeInsets.top, width: discSize, height: discSize)
    }

    // MARK: - Nội bộ

    /// Khung đĩa từ mép phải + mép dưới, kẹp trong vùng an toàn.
    private static func discFrame(
        trailing: CGFloat,
        bottom: CGFloat,
        bounds: CGRect,
        safeInsets: UIEdgeInsets
    ) -> CGRect {
        let size = discSize
        let minX = safeInsets.left + 4
        let maxX = max(minX, bounds.width - safeInsets.right - size)
        let x = min(max(trailing - size, minX), maxX)
        let minY = safeInsets.top + 8
        let maxY = max(minY, bounds.height - safeInsets.bottom - size)
        let y = min(max(bottom - size, minY), maxY)
        return CGRect(x: x, y: y, width: size, height: size)
    }

    /// Cửa sổ giao diện chính của app (level `.normal`, không phải lớp phủ), ưu tiên cửa sổ key.
    @MainActor
    private static func mainWindow() -> UIWindow? {
        guard let scene = AppMainWindowScene.current() else { return nil }
        let candidates = scene.windows.filter { !($0 is AppOverlayWindow) && $0.windowLevel == .normal && !$0.isHidden }
        return candidates.first { $0.isKeyWindow } ?? candidates.first
    }

    /// VC trình bày sâu nhất (bỏ qua VC đang bị đóng); không có gì trình bày ⇒ root.
    @MainActor
    private static func topLayer(of window: UIWindow) -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    /// Khung neo theo toạ độ cửa sổ nếu neo hợp lệ (đúng cửa sổ, đúng tầng trên cùng, nằm trong màn).
    @MainActor
    private static func validFrame(of view: UIView, in window: UIWindow, top: UIViewController?) -> CGRect? {
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
