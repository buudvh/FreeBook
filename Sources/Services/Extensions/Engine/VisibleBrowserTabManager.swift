import Foundation
import UIKit
import WebKit

// MARK: - Visible Browser Tab Manager
@MainActor
public final class VisibleBrowserTabManager: NSObject, UIAdaptivePresentationControllerDelegate {
    public static let shared = VisibleBrowserTabManager()

    private(set) var tabs: [VisibleBrowserTabItem] = []
    private(set) var activeTabId: String?
    private(set) var isHidden = false

    internal var containerViewController: TabbedVisibleBrowserViewController?
    internal var navController: UINavigationController?
    internal var isPresented = false
    internal var isDismissing = false

    static let stateDidChangeNotification = Notification.Name("VisibleBrowserStateDidChange")

    private override init() {
        super.init()
    }

    private func notifyStateChanged() {
        NotificationCenter.default.post(name: Self.stateDidChangeNotification, object: nil)
    }

    public func addTab(id: String, loader: VisibleWebViewLoader) {
        // Tránh thêm trùng tab ID. `presentUIIfNeeded()` được gọi lại ở mỗi lần
        // `load`/`loadAsync`, nên nhánh này là đường **lập trình**, không phải cử chỉ
        // người dùng: chỉ kích hoạt tab, không tự mở container (xem `activateTab`).
        if tabs.contains(where: { $0.id == id }) {
            activateTab(id: id)
            if isHidden, !VisibleBrowserSettings.opensMinimized {
                reopenContainer()
            }
            return
        }

        let rawTitle = loader.titleString.isEmpty ? "Trình duyệt" : loader.titleString

        // Tính toán tiêu đề phân biệt trùng tên: "Tab 1", "Tab 1 (2)", "Tab 1 (3)"...
        let matchingCount = tabs.filter { $0.rawTitle == rawTitle }.count
        let displayTitle = matchingCount > 0 ? "\(rawTitle) (\(matchingCount + 1))" : rawTitle

        let tabItem = VisibleBrowserTabItem(
            id: id,
            rawTitle: rawTitle,
            displayTitle: displayTitle,
            loader: loader
        )

        tabs.append(tabItem)
        activeTabId = id
        notifyStateChanged()

        if isHidden, let container = containerViewController {
            container.reloadTabs()
            // Cài đặt "mở ở chế độ thu nhỏ" bật thì giữ nguyên trạng thái thu nhỏ,
            // không tự bật container lên khi có tab mới.
            if !VisibleBrowserSettings.opensMinimized {
                reopenContainer()
            }
        } else if isDismissing {
            // Browser đang bị tắt (Đóng tất cả / đóng tab cuối): không nhét tab vào
            // container đang teardown. dismissContainer's completion sẽ present lại
            // container mới nếu vẫn còn tab.
        } else if !isPresented || navController == nil {
            openContainer(initialActiveId: id)
        } else {
            containerViewController?.reloadTabs()
        }
    }

    /// Chọn tab theo **cử chỉ người dùng** (bấm pill tab trong container): nếu đang thu
    /// nhỏ thì mở container lên.
    public func selectTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activateTab(id: id)
        if isHidden {
            reopenContainer()
        }
    }

    /// Kích hoạt tab **không** đổi trạng thái thu nhỏ/mở của container. Dùng cho mọi
    /// đường lập trình (extension gọi `load` lại trên loader đã có tab).
    internal func activateTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        containerViewController?.reloadTabs()
        notifyStateChanged()
    }

    public func removeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        let itemToRemove = tabs[index]
        tabs.remove(at: index)

        // Thực hiện cleanup nhẹ cho loader nếu chưa cleanup
        itemToRemove.loader.cleanUpQuietly()

        if tabs.isEmpty {
            dismissContainer()
        } else {
            if activeTabId == id {
                let newIndex = min(index, tabs.count - 1)
                activeTabId = tabs[newIndex].id
            }
            containerViewController?.reloadTabs()
        }
        notifyStateChanged()
    }

    public func removeAllTabs() {
        let currentTabs = tabs
        tabs.removeAll()
        activeTabId = nil

        for item in currentTabs {
            item.loader.cleanUpQuietly()
        }

        dismissContainer()
        notifyStateChanged()
    }

    /// Mở trình duyệt mới theo cài đặt: toàn màn hình (mặc định) hoặc thu nhỏ ngay.
    internal func openContainer(initialActiveId: String) {
        if VisibleBrowserSettings.opensMinimized {
            prepareContainerMinimized()
        } else {
            presentContainerView(initialActiveId: initialActiveId)
        }
    }

    /// Khởi tạo container ở trạng thái thu nhỏ: nạp view (để webview của tab được
    /// gắn vào đúng container, giống trạng thái sau khi vuốt xuống ẩn) nhưng **không**
    /// present lên bất kỳ view controller nào. Chỉ áp dụng cho trình duyệt mới.
    internal func prepareContainerMinimized() {
        guard !isPresented, !isDismissing else { return }

        let container = TabbedVisibleBrowserViewController()
        self.containerViewController = container
        self.navController = nil
        container.loadViewIfNeeded()

        self.isPresented = false
        self.isHidden = true
        notifyStateChanged()
    }

    internal func presentContainerView(initialActiveId: String) {
        guard !isPresented, !isDismissing else { return }

        let container = TabbedVisibleBrowserViewController()
        self.containerViewController = container

        let nav = UINavigationController(rootViewController: container)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        self.navController = nav

        guard let topVC = findTopViewController() else { return }

        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentContainerView(initialActiveId: initialActiveId)
            }
            return
        }

        self.isPresented = true
        self.isHidden = false
        topVC.present(nav, animated: true, completion: nil)
        notifyStateChanged()
    }

    public func hideContainer() {
        guard isPresented, !isDismissing else { return }
        isDismissing = true

        navController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.isPresented = false
            self.isDismissing = false
            self.navController = nil
            self.isHidden = true
            self.notifyStateChanged()
        }
    }

    public func reopenContainer() {
        guard isHidden, !tabs.isEmpty, let container = containerViewController else { return }

        // Tìm host **trước** khi bọc nav: nếu bọc trước rồi bỏ dở, `container` sẽ mắc
        // parent là nav vừa bị bỏ, và nav sau không bọc lại được nó.
        guard let topVC = findTopViewController() else { return }

        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.reopenContainer()
            }
            return
        }

        let nav = navigationController(wrapping: container)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        self.navController = nav

        self.isPresented = true
        self.isHidden = false
        topVC.present(nav, animated: true, completion: nil)
        notifyStateChanged()
        verifyReopenPresented(nav)
    }

    /// Bọc container vào một `UINavigationController` dùng được: tái dùng nav cũ nếu
    /// container vẫn còn là root của nó (UIKit không cho một VC có hai parent), ngược lại
    /// tách khỏi parent cũ rồi tạo nav mới.
    private func navigationController(wrapping container: TabbedVisibleBrowserViewController) -> UINavigationController {
        if let existing = container.parent as? UINavigationController,
           existing.presentingViewController == nil,
           existing.viewControllers.first === container {
            return existing
        }
        if container.parent != nil {
            container.willMove(toParent: nil)
            container.view.removeFromSuperview()
            container.removeFromParent()
        }
        return UINavigationController(rootViewController: container)
    }

    /// Lưới an toàn cho triệu chứng "bấm widget thì widget mất mà trình duyệt không mở":
    /// nếu sau khi animation kết thúc mà nav vẫn không được present (host từ chối), trả
    /// trạng thái về thu nhỏ để widget hiện lại thay vì kẹt không có gì trên màn hình.
    private func verifyReopenPresented(_ nav: UINavigationController) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak nav] in
            guard let self, let nav, self.navController === nav else { return }
            guard nav.presentingViewController == nil else { return }

            self.isPresented = false
            self.isHidden = true
            self.navController = nil
            self.notifyStateChanged()
        }
    }

    /// Tìm view controller trên cùng để present container.
    ///
    /// Chỉ nhận window ở level `.normal`: TTS widget và widget trình duyệt sống trong
    /// `UIWindow` riêng ở level `alert - 1` / `alert - 2`. Nếu present sheet lên window
    /// widget thì `notifyStateChanged()` ngay sau đó sẽ ẩn chính window đó (widget không
    /// còn điều kiện hiển thị vì `isHidden == false`), kéo theo sheet vừa present cũng
    /// biến mất — đúng triệu chứng "bấm widget thì widget mất mà trình duyệt không mở".
    private func findTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }

        let hostWindows = windowScene.windows.filter { $0.windowLevel == .normal && !$0.isHidden }
        guard let window = hostWindows.first(where: { $0.isKeyWindow })
                ?? hostWindows.first
                ?? windowScene.windows.first(where: { $0.windowLevel == .normal }),
              let rootVC = window.rootViewController else {
            return nil
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }

    internal func dismissContainer() {
        if !isPresented {
            navController = nil
            containerViewController = nil
            isDismissing = false
            isHidden = false
            notifyStateChanged()
            return
        }

        guard !isDismissing else { return }
        isDismissing = true

        navController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.isPresented = false
            self.isDismissing = false
            self.navController = nil
            self.containerViewController = nil
            self.isHidden = false
            self.notifyStateChanged()
            // Nếu có tab mới được thêm trong lúc dismiss (VD download vẫn đang dùng
            // browser để bypass Cloudflare), present lại container mới để webview
            // không bị bỏ rơi trong container đang bị hủy.
            if !self.tabs.isEmpty, let activeId = self.activeTabId {
                self.openContainer(initialActiveId: activeId)
            }
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        // Vuốt xuống = ẩn trình duyệt: giữ tabs + webview sống để có thể mở lại
        if !tabs.isEmpty {
            isPresented = false
            isDismissing = false
            navController = nil
            isHidden = true
            notifyStateChanged()
            return
        }
        isPresented = false
        isDismissing = false
        navController = nil
        containerViewController = nil
        notifyStateChanged()
    }
}
