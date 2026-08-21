import Foundation
import UIKit
import WebKit

// MARK: - Tabbed Container View Controller
@MainActor
public final class TabbedVisibleBrowserViewController: UIViewController {
    internal let tabBarScrollView = UIScrollView()
    internal let tabBarStackView = UIStackView()
    internal let containerView = UIView()

    internal var currentChildVC: UIViewController?

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        setupNavigationBar()
        setupUI()
        reloadTabs()
    }

    internal func setupNavigationBar() {
        title = "Trình duyệt"

        let hideButton = UIBarButtonItem(
            image: UIImage(systemName: "chevron.down"),
            style: .plain,
            target: self,
            action: #selector(handleHide)
        )
        hideButton.accessibilityLabel = "Ẩn trình duyệt"

        let closeAllButton = UIBarButtonItem(
            image: UIImage(systemName: "trash"),
            style: .plain,
            target: self,
            action: #selector(handleCloseAll)
        )
        closeAllButton.accessibilityLabel = "Đóng tất cả"

        navigationItem.rightBarButtonItems = [closeAllButton, hideButton]
    }

    @objc internal func handleHide() {
        VisibleBrowserTabManager.shared.hideContainer()
    }

    @objc internal func handleCloseAll() {
        VisibleBrowserTabManager.shared.removeAllTabs()
    }

    internal func setupUI() {
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

    internal func createTabPillView(tabItem: VisibleBrowserTabItem, isActive: Bool) -> UIView {
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

    @objc internal func handleTabTap(_ gesture: UITapGestureRecognizer) {
        guard let pillView = gesture.view, let id = pillView.accessibilityIdentifier else { return }
        VisibleBrowserTabManager.shared.selectTab(id: id)
    }

    @objc internal func handleCloseTabTap(_ sender: UIButton) {
        guard let id = sender.accessibilityIdentifier else { return }
        VisibleBrowserTabManager.shared.removeTab(id: id)
    }

    internal func displayChildViewController(_ childVC: UIViewController) {
        if currentChildVC == childVC { return }

        removeCurrentChildVC()

        addChild(childVC)
        childVC.view.frame = containerView.bounds
        childVC.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        containerView.addSubview(childVC.view)
        childVC.didMove(toParent: self)
        currentChildVC = childVC
    }

    internal func removeCurrentChildVC() {
        guard let child = currentChildVC else { return }
        child.willMove(toParent: nil)
        child.view.removeFromSuperview()
        child.removeFromParent()
        currentChildVC = nil
    }
}
