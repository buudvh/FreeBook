import UIKit

/// "Màn" đang hiện của cửa sổ chính (1.3.820) để đĩa góc biết lúc **đổi màn** — đẩy trang, mở Reader / sheet, quay lại.
///
/// Lý do: trước đây đổi màn mà chỗ đĩa khác chỗ cũ thì đĩa **trượt** sang chỗ mới (anh Bửu: Chi tiết → "+" → "Đọc" ⇒ đĩa
/// đang đứng cao trên cụm pill hiện giữa Reader rồi trượt xuống nút tai nghe). Nay container thấy `page` đổi ⇒ thu đĩa
/// tại chỗ, chờ hết chuyển cảnh + giữ yên 0,3 s rồi hiện thẳng ở chỗ mới.
///
/// - `page` = trang trên cùng của `UINavigationController` **đầu tiên đang hiện** (view trong cửa sổ chính, không ẩn)
///   trong tầng trình bày trên cùng — dừng ở đó, không đi sâu vào VC con của trang (`TabView` dạng trang bên trong một
///   trang không tính là đổi màn). Tầng không có nav ⇒ chính tầng đó. Chỉ đi cây **VC** (`children`), không quét view.
/// - `isTransitioning` = một VC trong chuỗi trình bày đang được trình bày / đóng, tầng trên cùng có `transitionCoordinator`,
///   hoặc nav đó đang đẩy / pop (kể cả vuốt back) — lúc đó khung các neo còn đang chạy.
@MainActor
enum MediaDiscScreenContext {
    struct Snapshot: Equatable {
        let page: ObjectIdentifier?
        let isTransitioning: Bool
    }

    static func current() -> Snapshot {
        guard let window = MediaDiscPlacement.mainWindow(), let root = window.rootViewController else {
            return Snapshot(page: nil, isTransitioning: false)
        }
        var transitioning = root.isBeingPresented || root.isBeingDismissed
        var layer = root
        while let presented = layer.presentedViewController {
            if presented.isBeingPresented || presented.isBeingDismissed { transitioning = true }
            // Cùng luật với `MediaDiscPlacement.topLayer`: VC đang bị đóng không còn là tầng trên cùng.
            if presented.isBeingDismissed { break }
            layer = presented
        }
        if layer.transitionCoordinator != nil { transitioning = true }

        guard let nav = visibleNavigationController(in: layer, window: window) else {
            return Snapshot(page: ObjectIdentifier(layer), isTransitioning: transitioning)
        }
        if nav.transitionCoordinator != nil { transitioning = true }
        let page = nav.topViewController.map { ObjectIdentifier($0) } ?? ObjectIdentifier(nav)
        return Snapshot(page: page, isTransitioning: transitioning)
    }

    /// Nav đầu tiên (duyệt theo tầng) có view đang ở cửa sổ chính và không ẩn — tab chưa chọn không có view trong cửa sổ.
    private static func visibleNavigationController(
        in layer: UIViewController,
        window: UIWindow
    ) -> UINavigationController? {
        var queue: [UIViewController] = [layer]
        var index = 0
        while index < queue.count {
            let controller = queue[index]
            index += 1
            if let nav = controller as? UINavigationController,
               nav.isViewLoaded, nav.view.window === window, !nav.view.isHidden {
                return nav
            }
            queue.append(contentsOf: controller.children)
        }
        return nil
    }
}
