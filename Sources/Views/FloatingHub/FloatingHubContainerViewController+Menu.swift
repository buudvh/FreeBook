import SwiftUI
import UIKit

/// Thẻ menu của nút hub nổi (1.3.524) — chỉ mở khi hub có từ 2 mục.
///
/// Menu sống trong **chính cửa sổ hub**: lớp nền trong suốt `menuBackdropView` phủ toàn màn và thẻ
/// `menuContainerView` cạnh nút. Khi menu mở, `FloatingHubUIWindow.hitTest` nhường **mọi** chạm cho cây view
/// của cửa sổ — nên cờ `FloatingHubViewModel.isMenuOpen` kẹt ở `true` là khoá cả app. `closeMenu` vì vậy
/// idempotent và được gọi ở mọi đường có thể bỏ quên menu.
///
/// Tách khỏi file chính để giữ mỗi file dưới 400 dòng; các member dùng chéo file là `internal`.
extension FloatingHubContainerViewController {
    func openMenu() {
        guard presentationReader.snapshot.items.count >= 2 else { return }
        viewModel.setMenuOpen(true)
        refreshMenu()
        layoutMenu()

        menuBackdropView.isHidden = false
        menuContainerView.isHidden = false
        menuContainerView.alpha = 0
        menuContainerView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
        UIView.animate(
            withDuration: Layout.menuAnimationDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
            animations: {
                self.menuContainerView.alpha = 1
                self.menuContainerView.transform = .identity
            },
            completion: nil
        )
    }

    /// Đóng menu. **Idempotent** — gọi ở mọi đường có thể làm cờ kẹt: ẩn hub, bắt đầu kéo, số mục < 2, mở
    /// sheet, mở một mục, đổi scene, `prepareForAppearance`. Cờ và lớp nền được hạ **ngay**, chỉ thẻ menu mờ dần.
    func closeMenu(animated: Bool) {
        viewModel.setMenuOpen(false)
        menuBackdropView.isHidden = true
        guard !menuContainerView.isHidden else { return }

        let finish = { [weak self] in
            // Menu được mở lại giữa lúc đang mờ dần ⇒ không được giấu thẻ vừa hiện.
            guard let self, !self.viewModel.isMenuOpen else { return }
            self.menuContainerView.isHidden = true
            self.menuContainerView.alpha = 1
            self.menuContainerView.transform = .identity
        }

        if animated {
            UIView.animate(
                withDuration: Layout.menuAnimationDuration,
                delay: 0,
                options: [.beginFromCurrentState, .curveEaseIn],
                animations: {
                    self.menuContainerView.alpha = 0
                    self.menuContainerView.transform = CGAffineTransform(scaleX: 0.96, y: 0.96)
                },
                completion: { _ in finish() }
            )
        } else {
            finish()
        }
    }

    /// Gán lại nội dung thẻ theo snapshot hiện tại; tạo hosting controller ở lần mở đầu tiên.
    func refreshMenu() {
        let snapshot = presentationReader.snapshot
        let menu = FloatingHubMenuView(
            items: snapshot.items,
            unreadCount: snapshot.unreadCount,
            onSelect: { [weak self] kind in
                self?.open(kind)
            }
        )

        if let hosting = menuHostingController {
            hosting.rootView = menu
            return
        }

        let hosting = UIHostingController(rootView: menu)
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        addChild(hosting)
        menuContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        menuHostingController = hosting
    }

    /// Đặt thẻ cạnh nút về phía **xa mép**, cách 8pt; tâm dọc theo tâm nút, kẹp trong vùng an toàn.
    /// Dùng `bounds` + `center` (không `frame`) vì thẻ có thể đang mang `transform` của animation.
    func layoutMenu() {
        guard viewModel.isMenuOpen, let hosting = menuHostingController else { return }
        let bounds = view.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }

        let fitting = hosting.sizeThatFits(
            in: CGSize(width: FloatingHubMenuView.width, height: .greatestFiniteMagnitude)
        )
        let size = CGSize(width: FloatingHubMenuView.width, height: ceil(fitting.height))
        let hubCenter = widgetContainerView.center
        let halfHub = Layout.size / 2

        var x = viewModel.edgeDirection == .right
            ? hubCenter.x - halfHub - Layout.menuSpacing - size.width / 2
            : hubCenter.x + halfHub + Layout.menuSpacing + size.width / 2
        let minX = view.safeAreaInsets.left + Layout.horizontalMargin + size.width / 2
        let maxX = bounds.width - view.safeAreaInsets.right - Layout.horizontalMargin - size.width / 2
        if minX <= maxX {
            x = min(max(x, minX), maxX)
        }
        let y = clampedY(hubCenter.y, height: size.height, screenHeight: bounds.height)

        menuContainerView.bounds = CGRect(origin: .zero, size: size)
        menuContainerView.center = CGPoint(x: x, y: y)
        hosting.view.frame = menuContainerView.bounds
    }
}
