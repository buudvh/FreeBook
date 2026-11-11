import SwiftUI
import UIKit

/// Root view controller của cửa sổ đĩa nghe (`MediaDiscWindow`, 1.3.808). Giữ hai nội dung SwiftUI:
/// - `discView` — vùng duy nhất nhận chạm — chứa mặt đĩa (`MediaDiscFaceButton(.corner)`): **nửa viên thuốc** 68 × 52 dính
///   mép trái / phải (anh Bửu duyệt mockup 2026-11-11), lúc đang kéo là hình tròn 52 pt.
/// - Một view 1×1 không nhận chạm giữ sheet điều khiển nhanh (`MediaDiscSheetHost`, 1.3.812): chạm nửa viên ⇒ sheet ở đây.
///
/// - Chỗ đứng do `MediaDiscPlacement.resolve` quyết mỗi lượt `updateDisc` từ chỗ đã nhớ (`MediaDiscPositionStore`); đổi chỗ
///   ⇒ trượt lò xo, hiện / ẩn ⇒ phóng / thu (chỉ `transform` — alpha < 1 trên lớp cha tắt nhoè của kính).
/// - **Chạm và kéo ở lớp UIKit** (`+Drag`, khuôn nút hub): mặt đĩa SwiftUI không có cử chỉ nào ⇒ bộ nhận của UIKit chạy (bài
///   học 1.3.812: nút SwiftUI bắt chạm ngay lúc chạm xuống). Chạm ⇒ sheet; kéo ⇒ thành tròn theo tay, thả ⇒ bám mép gần
///   hơn, nhường nút hub / trình duyệt cùng mép (`FloatingWidgetLayoutCoordinator`), lưu chỗ.
/// - **Ẩn ngay, hiện chậm** (1.3.812): màn trên cùng không cho hiện (màn xem phim, bàn phím, hộp thoại…) ⇒ thu ngay; đĩa
///   đang ẩn mà nay được hiện ⇒ chỉ hiện khi điều kiện đã giữ đủ 0,3 s.
/// - **Đổi màn ⇒ đĩa đứng yên** (1.3.865, anh Bửu: "mọi màn, sheet đều hiển thị viên thuốc"; thay luật thu tại chỗ của
///   1.3.820): đĩa ở mọi màn nên không thu / hiện lại; đang chuyển cảnh (`MediaDiscScreenContext.isTransitioning`) ⇒ đứng
///   yên, hết chuyển cảnh mà màn mới có neo phải né ⇒ trượt tới chỗ mới.
/// - Lượt tính lại: neo đổi (`MediaDiscAnchorRegistry.onChange`), manager báo đổi trạng thái, xoay màn / đổi vùng an toàn,
///   và đồng hồ 0,4 s (`setPolling`, chế độ `.common`) chỉ khi cửa sổ đang hiện. Tay đang giữ đĩa ⇒ không dời.
/// - Giữ chỗ ở `FloatingWidgetLayoutCoordinator` (`.mediaDisc`, đúng mép đang dính) khi đĩa hiện: nút hub / trình duyệt vừa
///   thả / vừa hiện sẽ né.
@MainActor
final class MediaDiscContainerViewController: UIViewController {
    let discView = UIView()
    /// Đĩa đang hiện (không đang thu / đã ẩn) ⇒ cửa sổ nhận chạm trong khung đĩa.
    private(set) var isDiscInteractive = false

    // Trạng thái kéo — `internal` vì `+Drag.swift` dùng.
    var panGesture: UIPanGestureRecognizer?
    var isDragging = false
    var dragStartCenter: CGPoint = .zero
    /// Chỗ ở `FloatingWidgetLayoutCoordinator` phải **mở** lại (chỉ `resolve` mở được; `refresh` chỉ cập nhật chỗ đã có).
    /// Thả tay đã `resolve` ⇒ `+Drag` hạ cờ.
    var needsSlotClaim = true

    private var discHost: UIHostingController<AnyView>?
    private var sheetHost: UIHostingController<AnyView>?
    private var pollTimer: Timer?
    private var isShowingDisc = false
    /// Lúc đĩa đang ẩn bắt đầu được phép hiện — hiện thật khi đã giữ đủ `showDelay`.
    private var pendingShowSince: Date?
    private var pendingShowWork: DispatchWorkItem?

    private enum Layout {
        static let pollInterval: TimeInterval = 0.4
        static let hiddenScale: CGFloat = 0.4
        /// Lệch dưới mức này coi như đứng yên (không chạy hiệu ứng mỗi lượt hỏi).
        static let moveTolerance: CGFloat = 0.5
        static let showDelay: TimeInterval = 0.3
        /// Màn đang chuyển cảnh: hỏi lại sau nhịp này.
        static let transitionRecheck: TimeInterval = 0.1
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        // Chỗ giữ sheet: 1×1, luôn hiện, không nhận chạm (sheet là VC trình bày riêng nên vẫn nhận chạm bình thường).
        let sheets = makeHost(MediaDiscSheetHost())
        addChild(sheets)
        sheets.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        sheets.view.isUserInteractionEnabled = false
        view.addSubview(sheets.view)
        sheets.didMove(toParent: self)
        sheetHost = sheets

        discView.bounds = CGRect(origin: .zero, size: MediaDiscPlacement.pillSize)
        discView.backgroundColor = .clear
        discView.isHidden = true
        view.addSubview(discView)

        let disc = makeHost(MediaDiscFaceButton())
        addChild(disc)
        disc.view.frame = discView.bounds
        disc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        discView.addSubview(disc.view)
        disc.didMove(toParent: self)
        discHost = disc

        setupDiscGestures()

        MediaDiscAnchorRegistry.shared.onChange = { [weak self] in
            self?.updateDisc(animated: true)
        }
    }

    /// Cửa sổ riêng không thừa hưởng `.tint` / `modelContainer` của `MainTabView` ⇒ gắn ở gốc (sheet thừa hưởng tiếp).
    private func makeHost<Content: View>(_ content: Content) -> UIHostingController<AnyView> {
        let tinted = content.appAccentTint()
        let rootView: AnyView
        if let container = MediaDiscWindowManager.shared.modelContainer {
            rootView = AnyView(tinted.modelContainer(container))
        } else {
            rootView = AnyView(tinted)
        }
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        hosting.safeAreaRegions = []
        return hosting
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
        cancelDrag()
        cancelPendingShow()
        setDiscShown(false, frame: nil, edge: nil, animated: false)
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
            cancelDrag()
            cancelPendingShow()
            setDiscShown(false, frame: nil, edge: nil, animated: false)
            return
        }
        let placement = MediaDiscPlacement.resolve(
            bounds: view.bounds,
            safeInsets: view.safeAreaInsets,
            position: MediaDiscPositionStore.load()
        )
        guard MediaDiscWindowManager.shared.isDiscAllowed, !placement.isBlocked else {
            cancelDrag()
            cancelPendingShow()
            setDiscShown(false, frame: nil, edge: nil, animated: animated)
            return
        }
        // Tay đang giữ đĩa: không dời.
        if isDragging { return }
        let screen = MediaDiscScreenContext.current()
        if screen.isTransitioning {
            // Khung các neo còn đang chạy: đĩa đang hiện (cùng màn) thì đứng yên; đĩa đang ẩn thì chưa đếm thời gian chờ.
            if !isShowingDisc {
                pendingShowSince = nil
                scheduleShowCheck(after: Layout.transitionRecheck)
            }
            return
        }
        if !isShowingDisc, !isShowDelayElapsed() { return }
        setDiscShown(true, frame: placement.frame, edge: placement.edge, animated: animated)
    }

    // MARK: - Hiện chậm

    /// Đĩa đang ẩn mà nay được hiện: chỉ hiện khi điều kiện đã giữ đủ `showDelay`; chưa đủ ⇒ hẹn một lượt tính lại.
    private func isShowDelayElapsed() -> Bool {
        let now = Date()
        guard let since = pendingShowSince else {
            pendingShowSince = now
            scheduleShowCheck(after: Layout.showDelay)
            return false
        }
        let elapsed = now.timeIntervalSince(since)
        guard elapsed < Layout.showDelay - 0.01 else {
            cancelPendingShow()
            return true
        }
        scheduleShowCheck(after: Layout.showDelay - elapsed)
        return false
    }

    private func scheduleShowCheck(after delay: TimeInterval) {
        pendingShowWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.updateDisc(animated: true)
            }
        }
        pendingShowWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelPendingShow() {
        pendingShowSince = nil
        pendingShowWork?.cancel()
        pendingShowWork = nil
    }

    // MARK: - Hiện / ẩn / dời

    private func setDiscShown(_ shown: Bool, frame: CGRect?, edge: EdgeDirection?, animated: Bool) {
        if shown, let frame, let edge {
            MediaDiscWindowManager.shared.noteDiscEdge(edge)
            let target = CGPoint(x: frame.midX, y: frame.midY)
            let size = frame.size
            if !isShowingDisc {
                isShowingDisc = true
                discView.layer.removeAllAnimations()
                discView.bounds = CGRect(origin: .zero, size: size)
                discView.center = target
                discView.transform = CGAffineTransform(scaleX: Layout.hiddenScale, y: Layout.hiddenScale)
                discView.isHidden = false
                animate(animated, motion: .spring) {
                    self.discView.transform = .identity
                }
            } else if hypot(discView.center.x - target.x, discView.center.y - target.y) > Layout.moveTolerance
                        || discView.bounds.size != size || discView.transform != .identity {
                animate(animated, motion: .spring) {
                    self.discView.bounds = CGRect(origin: .zero, size: size)
                    self.discView.center = target
                    self.discView.transform = .identity
                }
            }
            isDiscInteractive = true
            claimSlot(frame, edge: edge)
        } else if isShowingDisc {
            isShowingDisc = false
            isDiscInteractive = false
            releaseSlot()
            animate(animated, motion: .collapse) {
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

    enum Motion {
        case spring
        /// Co về hình tròn lúc bắt đầu kéo.
        case grab
        case collapse
    }

    func animate(
        _ animated: Bool,
        motion: Motion,
        changes: @escaping () -> Void,
        completion: (() -> Void)? = nil
    ) {
        guard animated else {
            changes()
            completion?()
            return
        }
        let duration: TimeInterval
        let damping: CGFloat
        let curve: UIView.AnimationOptions
        switch motion {
        case .spring:
            duration = 0.34
            damping = 0.82
            curve = .curveEaseOut
        case .grab:
            duration = 0.18
            damping = 1
            curve = .curveEaseOut
        case .collapse:
            duration = 0.18
            damping = 1
            curve = .curveEaseIn
        }
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: damping,
            initialSpringVelocity: 0,
            options: [.allowUserInteraction, .beginFromCurrentState, curve],
            animations: changes
        ) { _ in
            completion?()
        }
    }

    // MARK: - Giữ chỗ với nút hub / trình duyệt

    private func claimSlot(_ frame: CGRect, edge: EdgeDirection) {
        let coordinator = FloatingWidgetLayoutCoordinator.shared
        if needsSlotClaim {
            needsSlotClaim = false
            // Lúc hiện đĩa không nhường: khoảng tìm chỉ một điểm ⇒ `resolve` chỉ để mở chỗ. Nhường chỉ lúc thả tay (`+Drag`).
            _ = coordinator.resolve(
                id: .mediaDisc,
                edge: edge,
                proposedCenterY: frame.midY,
                height: frame.height,
                minY: frame.midY,
                maxY: frame.midY
            )
        }
        coordinator.refresh(id: .mediaDisc, edge: edge, centerY: frame.midY, height: frame.height)
    }

    private func releaseSlot() {
        FloatingWidgetLayoutCoordinator.shared.unregister(.mediaDisc)
        needsSlotClaim = true
    }
}
