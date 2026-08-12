import Foundation
import UIKit
import WebKit

// MARK: - Visible Browser Tab Item Model
@MainActor
public struct VisibleBrowserTabItem: Identifiable {
    public let id: String
    public let rawTitle: String
    public var displayTitle: String
    public let loader: VisibleWebViewLoader

    public init(id: String, rawTitle: String, displayTitle: String, loader: VisibleWebViewLoader) {
        self.id = id
        self.rawTitle = rawTitle
        self.displayTitle = displayTitle
        self.loader = loader
    }
}

// MARK: - Visible Browser Tab Manager
@MainActor
public final class VisibleBrowserTabManager: NSObject, UIAdaptivePresentationControllerDelegate {
    public static let shared = VisibleBrowserTabManager()

    private(set) var tabs: [VisibleBrowserTabItem] = []
    private(set) var activeTabId: String?

    private var containerViewController: TabbedVisibleBrowserViewController?
    private var navController: UINavigationController?
    private var isPresented = false
    private var isDismissing = false

    private override init() {
        super.init()
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

        if !isPresented || navController == nil {
            presentContainerView(initialActiveId: id)
        } else {
            containerViewController?.reloadTabs()
        }
    }

    public func selectTab(id: String) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        activeTabId = id
        containerViewController?.reloadTabs()
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
    }

    public func removeAllTabs() {
        let currentTabs = tabs
        tabs.removeAll()
        activeTabId = nil

        for item in currentTabs {
            item.loader.cleanUpQuietly()
        }

        dismissContainer()
    }

    private func presentContainerView(initialActiveId: String) {
        guard !isPresented, !isDismissing else { return }

        let container = TabbedVisibleBrowserViewController()
        self.containerViewController = container

        let nav = UINavigationController(rootViewController: container)
        nav.modalPresentationStyle = .pageSheet
        nav.presentationController?.delegate = self
        self.navController = nav

        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              let window = windowScene.windows.first(where: { $0.isKeyWindow }) ?? windowScene.windows.first,
              let rootVC = window.rootViewController else {
            return
        }

        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }

        if topVC.isBeingPresented || topVC.isBeingDismissed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.presentContainerView(initialActiveId: initialActiveId)
            }
            return
        }

        self.isPresented = true
        topVC.present(nav, animated: true, completion: nil)
    }

    private func dismissContainer() {
        guard isPresented, !isDismissing else { return }
        isDismissing = true

        navController?.dismiss(animated: true) { [weak self] in
            guard let self = self else { return }
            self.isPresented = false
            self.isDismissing = false
            self.navController = nil
            self.containerViewController = nil
        }
    }

    public func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        isPresented = false
        isDismissing = false
        navController = nil
        containerViewController = nil

        let currentTabs = tabs
        tabs.removeAll()
        activeTabId = nil

        for item in currentTabs {
            item.loader.cleanUpQuietly()
        }
    }
}

// MARK: - Tabbed Container View Controller
@MainActor
public final class TabbedVisibleBrowserViewController: UIViewController {
    private let tabBarScrollView = UIScrollView()
    private let tabBarStackView = UIStackView()
    private let containerView = UIView()

    private var currentChildVC: UIViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUI()
        reloadTabs()
    }

    private func setupNavigationBar() {
        title = "Trình duyệt"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Đóng tất cả",
            style: .done,
            target: self,
            action: #selector(handleCloseAll)
        )
    }

    @objc private func handleCloseAll() {
        VisibleBrowserTabManager.shared.removeAllTabs()
    }

    private func setupUI() {
        tabBarScrollView.showsHorizontalScrollIndicator = false
        tabBarScrollView.alwaysBounceHorizontal = true
        tabBarScrollView.translatesAutoresizingMaskIntoConstraints = false

        tabBarStackView.axis = .horizontal
        tabBarStackView.alignment = .center
        tabBarStackView.spacing = 8
        tabBarStackView.translatesAutoresizingMaskIntoConstraints = false

        containerView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabBarScrollView)
        tabBarScrollView.addSubview(tabBarStackView)
        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            tabBarScrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            tabBarScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabBarScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabBarScrollView.heightAnchor.constraint(equalToConstant: 44),

            tabBarStackView.topAnchor.constraint(equalTo: tabBarScrollView.topAnchor, constant: 4),
            tabBarStackView.bottomAnchor.constraint(equalTo: tabBarScrollView.bottomAnchor, constant: -4),
            tabBarStackView.leadingAnchor.constraint(equalTo: tabBarScrollView.leadingAnchor, constant: 12),
            tabBarStackView.trailingAnchor.constraint(equalTo: tabBarScrollView.trailingAnchor, constant: -12),
            tabBarStackView.heightAnchor.constraint(equalToConstant: 36),

            containerView.topAnchor.constraint(equalTo: tabBarScrollView.bottomAnchor),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    public func reloadTabs() {
        let manager = VisibleBrowserTabManager.shared
        let tabs = manager.tabs
        let activeId = manager.activeTabId

        // Cập nhật tiêu đề Navigation
        if tabs.count > 1 {
            title = "Trình duyệt (\(tabs.count) tab)"
        } else if let active = tabs.first(where: { $0.id == activeId }) {
            title = active.displayTitle
        } else {
            title = "Trình duyệt"
        }

        // Xóa các tab button cũ
        for subview in tabBarStackView.arrangedSubviews {
            tabBarStackView.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        // Tạo lại danh sách tab pill button
        for tabItem in tabs {
            let isActive = (tabItem.id == activeId)
            let tabPillView = createTabPillView(tabItem: tabItem, isActive: isActive)
            tabBarStackView.addArrangedSubview(tabPillView)
        }

        // Cập nhật WebView hiển thị trong containerView
        if let activeItem = tabs.first(where: { $0.id == activeId }) {
            displayChildViewController(activeItem.loader.viewController)
        } else if let firstItem = tabs.first {
            displayChildViewController(firstItem.loader.viewController)
        } else {
            removeCurrentChildVC()
        }
    }

    private func createTabPillView(tabItem: VisibleBrowserTabItem, isActive: Bool) -> UIView {
        let pillView = UIView()
        pillView.layer.cornerRadius = 18
        pillView.clipsToBounds = true
        pillView.backgroundColor = isActive ? UIColor.systemBlue : UIColor.systemGray6

        let titleLabel = UILabel()
        titleLabel.text = tabItem.displayTitle
        titleLabel.font = .systemFont(ofSize: 13, weight: isActive ? .bold : .medium)
        titleLabel.textColor = isActive ? .white : .label
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let closeButton = UIButton(type: .system)
        let closeImage = UIImage(systemName: "xmark.circle.fill")
        closeButton.setImage(closeImage, for: .normal)
        closeButton.tintColor = isActive ? UIColor.white.withAlphaComponent(0.8) : UIColor.tertiaryLabel
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Tap gesture chọn tab
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTabTap(_:)))
        pillView.addGestureRecognizer(tapGesture)
        pillView.isUserInteractionEnabled = true
        pillView.accessibilityIdentifier = tabItem.id

        // Action nút đóng tab
        closeButton.accessibilityIdentifier = tabItem.id
        closeButton.addTarget(self, action: #selector(handleCloseTabTap(_:)), for: .touchUpInside)

        pillView.addSubview(titleLabel)
        pillView.addSubview(closeButton)

        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: pillView.leadingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),

            closeButton.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 6),
            closeButton.trailingAnchor.constraint(equalTo: pillView.trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: pillView.centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 20),
            closeButton.heightAnchor.constraint(equalToConstant: 20),

            pillView.heightAnchor.constraint(equalToConstant: 36)
        ])

        return pillView
    }

    @objc private func handleTabTap(_ gesture: UITapGestureRecognizer) {
        guard let pillView = gesture.view, let id = pillView.accessibilityIdentifier else { return }
        VisibleBrowserTabManager.shared.selectTab(id: id)
    }

    @objc private func handleCloseTabTap(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier else { return }
        VisibleBrowserTabManager.shared.removeTab(id: id)
    }

    private func displayChildViewController(_ childVC: UIViewController) {
        if currentChildVC == childVC { return }

        removeCurrentChildVC()

        addChild(childVC)
        childVC.view.frame = containerView.bounds
        childVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(childVC.view)
        childVC.didMove(toParent: self)
        currentChildVC = childVC
    }

    private func removeCurrentChildVC() {
        guard let child = currentChildVC else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        currentChildVC = nil
    }
}
