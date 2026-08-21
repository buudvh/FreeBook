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
        // Tránh thêm trùng tab ID
        if let _ = tabs.firstIndex(where: { $0.id == id }) {
            selectTab(id: id)
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
            reopenContainer()
        } else if isDismissing {
            // Browser đang bị tắt (Đóng tất cả / đóng tab cuối): không nhét tab vào
            // container đang teardown. dismissContainer's completion sẽ present lại
            // container mới nếu vẫn còn tab.
        } else if !isPresented || navController == nil {
            presentContainerView(initialActiveId: id)
        } else {
            containerViewController?.reloadTabs()
        }
    }

    public func selectTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        containerViewController?.reloadTabs()
        if isHidden {
            reopenContainer()
        }
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

        let nav = UINavigationController(rootViewController: container)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        self.navController = nav

        guard let topVC = findTopViewController() else { return }

        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.reopenContainer()
            }
            return
        }

        self.isPresented = true
        self.isHidden = false
        topVC.present(nav, animated: true, completion: nil)
        notifyStateChanged()
    }

    private func findTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
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
                self.presentContainerView(initialActiveId: activeId)
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
