import UIKit

/// Đổi tab rồi quay lại ⇒ thấy trang gốc của tab. Rời một tab đang ở trang con (Chi tiết, Tìm, Thể loại, trang cài đặt
/// con…) thì `MainTabView` tăng mã `.id` của tab đó để SwiftUI tạo lại nó ngầm; tab đang ở trang gốc giữ nguyên (không
/// tải lại Khám phá, giữ chỗ cuộn). Chỉ đặt lại tab **vừa rời**, không đụng tab đang vào: lối chuyển tab tự động (widget
/// TTS mở Reader ở tab Kệ) cần tab đích còn nguyên state trong cùng nhịp.
///
/// Các tab gốc dùng `NavigationStack` không `path` (trang con mở bằng cờ `isPresented` và `NavigationLink`) nên không
/// đóng được bằng state ⇒ **chỉ đọc** ngăn xếp `UINavigationController` của tab trong cửa sổ chính, không sửa gì.
extension MainTabView {
    /// Có nên tạo lại tab `index` (trong `tabCount` tab) lúc rời nó không. Không đọc được cây UIKit, hoặc thanh tab không
    /// liệt kê đủ `tabCount` tab (chỉ số có thể trỏ nhầm tab) ⇒ đặt lại (đúng ý "về màn đầu của tab").
    @MainActor
    static func shouldResetTab(at index: Int, of tabCount: Int) -> Bool {
        guard let tabBarController = mainTabBarController(),
              let tabs = tabBarController.viewControllers, tabs.count == tabCount, tabs.indices.contains(index) else {
            AppLogger.shared.log("❌ [TabReset] Không đọc được UITabBarController đủ \(tabCount) tab ⇒ đặt lại tab \(index)")
            return true
        }
        // Sheet / màn toàn màn (Reader, phim, truyện tranh) đang phủ: tạo lại tab có thể đóng mất màn đó (vd Reader mở từ
        // Chi tiết trong Khám phá, widget TTS chuyển sang tab Kệ) ⇒ giữ nguyên.
        var current: UIViewController? = tabs[index]
        while let controller = current {
            if controller.presentedViewController != nil { return false }
            current = controller.parent
        }
        let stacks = descendants(of: tabs[index]).compactMap { $0 as? UINavigationController }
        guard !stacks.isEmpty else {
            AppLogger.shared.log("❌ [TabReset] Tab \(index) không có UINavigationController ⇒ đặt lại")
            return true
        }
        return stacks.contains { $0.viewControllers.count > 1 }
    }

    /// Thanh tab của cửa sổ chính. Dò mọi cửa sổ (ưu tiên cửa sổ key) thay vì tin cửa sổ key: widget TTS, hub, ngăn kéo
    /// là cửa sổ phủ riêng, không có thanh tab.
    @MainActor
    private static func mainTabBarController() -> UITabBarController? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .sorted { $0.isKeyWindow && !$1.isKeyWindow }
        for window in windows {
            guard let root = window.rootViewController else { continue }
            if let tabBarController = descendants(of: root).lazy.compactMap({ $0 as? UITabBarController }).first {
                return tabBarController
            }
        }
        return nil
    }

    /// Mọi view controller con (theo `children`, không đi vào màn được present), duyệt theo tầng từ `root`.
    @MainActor
    private static func descendants(of root: UIViewController) -> [UIViewController] {
        var result: [UIViewController] = []
        var queue: [UIViewController] = [root]
        while !queue.isEmpty {
            let controller = queue.removeFirst()
            result.append(controller)
            queue.append(contentsOf: controller.children)
        }
        return result
    }
}
