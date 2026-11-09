import SwiftUI
import UIKit

/// Root view controller của cửa sổ đĩa nghe góc dưới phải (`MediaDiscWindow`, 1.3.808). Giữ **một** `discView` 52×52 —
/// vùng duy nhất nhận chạm — chứa nội dung SwiftUI (`MediaDiscContentView`: mặt đĩa + sheet điều khiển nhanh).
///
/// - Chỗ đứng do `MediaDiscPlacement.resolve` quyết mỗi lượt `updateDisc`; đổi chỗ ⇒ trượt lò xo, hiện / ẩn ⇒ phóng / thu
///   (chỉ `transform` — alpha < 1 trên lớp cha tắt nhoè của kính `FloatingGlassBackground`).
/// - Lượt tính lại: neo đổi (`MediaDiscAnchorRegistry.onChange`), manager báo đổi trạng thái, xoay màn / đổi vùng an toàn,
///   và đồng hồ 0,4 s (`setPolling`, chế độ `.common` để chạy cả lúc đang cuộn) chỉ khi cửa sổ đang hiện.
/// - Giữ chỗ mép phải ở `FloatingWidgetLayoutCoordinator` (`.mediaDisc`) khi đĩa hiện: nút hub vừa thả / vừa hiện sẽ né
///   (đĩa không nhường — chỗ của nó do neo quyết).
@MainActor
final class MediaDiscContainerViewController: UIViewController {
    let discView = UIView()
    /// Đĩa đang hiện (không đang thu / đã ẩn) ⇒ cửa sổ nhận chạm trong khung đĩa.
    private(set) var isDiscInteractive = false

    private var hostingController: UIHostingController<AnyView>?
    private var pollTimer: Timer?
    private var isShowingDisc = false
    /// Chỗ ở `FloatingWidgetLayoutCoordinator` phải **mở** lại (chỉ `resolve` mở được; `refresh` chỉ cập nhật chỗ đã có).
    private var needsSlotClaim = true

    private enum Layout {
        static let pollInterval: TimeInterval = 0.4
        static let hiddenScale: CGFloat = 0.4
        /// Lệch dưới mức này coi như đứng yên (không chạy hiệu ứng mỗi lượt hỏi).
        static let moveTolerance: CGFloat = 0.5
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        let size = MediaDiscPlacement.discSize
        discView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        discView.backgroundColor = .clear
        discView.isHidden = true
        view.addSubview(discView)

        // Cửa sổ riêng không thừa hưởng `.tint` / `modelContainer` của `MainTabView` ⇒ gắn ở gốc (sheet thừa hưởng tiếp).
        let content = MediaDiscContentView().appAccentTint()
        let rootView: AnyView
        if let container = MediaDiscWindowManager.shared.modelContainer {
            rootView = AnyView(content.modelContainer(container))
        } else {
            rootView = AnyView(content)
        }
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        addChild(hosting)
        hosting.view.frame = discView.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        discView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        hostingController = hosting

        MediaDiscAnchorRegistry.shared.onChange = { [weak self] in
            self?.updateDisc(animated: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateDisc(animated: false)
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: nil) { [weak self] _ in
            self?.updateDisc(animated: true)
        }
    }

    // MARK: - Manager gọi

    func windowDidShow() {
        needsSlotClaim = true
        view.setNeedsLayout()
        updateDisc(animated: true)
    }

    func windowDidHide() {
        setDiscShown(false, frame: nil, animated: false)
    }

    /// Bật / tắt lượt hỏi định kỳ (cửa sổ hiện và app không ở nền).
    func setPolling(_ enabled: Bool) {
        guard enabled else {
            pollTimer?.invalidate()
            pollTimer = nil
            return
        }
        guard pollTimer == nil else { return }
        let timer = Timer(timeInterval: Layout.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateDisc(animated: true)
            }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    /// Tính lại chỗ + hiện/ẩn đĩa.
    func updateDisc(animated: Bool) {
        guard isViewLoaded, view.bounds.width > 0, view.bounds.height > 0 else { return }
        guard let window = view.window, !window.isHidden else {
            setDiscShown(false, frame: nil, animated: false)
            return
        }
        let placement = MediaDiscPlacement.resolve(bounds: view.bounds, safeInsets: view.safeAreaInsets)
        let shouldShow = MediaDiscWindowManager.shared.isDiscAllowed && !placement.isBlocked
        setDiscShown(shouldShow, frame: placement.frame, animated: animated)
    }

    // MARK: - Hiện / ẩn / dời

    private func setDiscShown(_ shown: Bool, frame: CGRect?, animated: Bool) {
        if shown, let frame {
            let target = CGPoint(x: frame.midX, y: frame.midY)
            if !isShowingDisc {
                isShowingDisc = true
                discView.layer.removeAllAnimations()
                discView.center = target
                discView.transform = CGAffineTransform(scaleX: Layout.hiddenScale, y: Layout.hiddenScale)
                discView.isHidden = false
                animate(animated, spring: true) {
                    self.discView.transform = .identity
                }
            } else if hypot(discView.center.x - target.x, discView.center.y - target.y) > Layout.moveTolerance {
                animate(animated, spring: true) {
                    self.discView.center = target
                }
            }
            isDiscInteractive = true
            claimSlot(frame)
        } else if isShowingDisc {
            isShowingDisc = false
            isDiscInteractive = false
            releaseSlot()
            animate(animated, spring: false) {
                self.discView.transform = CGAffineTransform(scaleX: Layout.hiddenScale, y: Layout.hiddenScale)
            } completion: {
                // Đã hiện lại trong lúc đang thu ⇒ giữ nguyên.
                guard !self.isShowingDisc else { return }
                self.discView.isHidden = true
                self.discView.transform = .identity
            }
        }
        MediaDiscWindowManager.shared.noteDiscShown(isShowingDisc)
    }

    private func animate(
        _ animated: Bool,
        spring: Bool,
        changes: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard animated else {
            changes()
            completion?()
            return
        }
        let curve: UIView.AnimationOptions = spring ? .curveEaseOut : .curveEaseIn
        UIView.animate(
            withDuration: spring ? 0.34 : 0.18,
            delay: 0,
            usingSpringWithDamping: spring ? 0.82 : 1,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, curve],
            animations: changes
        ) { _ in
            completion?()
        }
    }

    // MARK: - Giữ chỗ với nút hub

    private func claimSlot(_ frame: CGRect) {
        let coordinator = FloatingWidgetLayoutCoordinator.shared
        if needsSlotClaim {
            needsSlotClaim = false
            // Đĩa không nhường: khoảng tìm chỉ một điểm ⇒ `resolve` chỉ để mở chỗ.
            _ = coordinator.resolve(
                id: .mediaDisc,
                edge: .right,
                proposedCenterY: frame.midY,
                height: frame.height,
                minY: frame.midY,
                maxY: frame.midY
            )
        }
        coordinator.refresh(id: .mediaDisc, edge: .right, centerY: frame.midY, height: frame.height)
    }

    private func releaseSlot() {
        FloatingWidgetLayoutCoordinator.shared.unregister(.mediaDisc)
        needsSlotClaim = true
    }
}
