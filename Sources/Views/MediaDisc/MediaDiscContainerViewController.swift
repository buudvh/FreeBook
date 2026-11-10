import SwiftUI
import UIKit

/// Root view controller của cửa sổ đĩa nghe góc dưới phải (`MediaDiscWindow`, 1.3.808). Giữ hai nội dung SwiftUI:
/// - `discView` 52×52 — vùng duy nhất nhận chạm — chứa nút đĩa góc (`MediaDiscFaceButton(.corner)`).
/// - Một view 1×1 không nhận chạm giữ sheet điều khiển nhanh (`MediaDiscSheetHost`, 1.3.812): chạm đĩa góc hay đĩa ở ô giữa
///   thanh tab đều mở sheet ở đây.
///
/// - Chỗ đứng do `MediaDiscPlacement.resolve` quyết mỗi lượt `updateDisc`; đổi chỗ ⇒ trượt lò xo, hiện / ẩn ⇒ phóng / thu
///   (chỉ `transform` — alpha < 1 trên lớp cha tắt nhoè của kính `FloatingGlassBackground`).
/// - **Ẩn ngay, hiện chậm** (1.3.812): màn trên cùng không cho hiện (thanh tab tự có ô đĩa, màn xem phim, bàn phím…) ⇒ thu
///   ngay; đĩa đang ẩn mà nay được hiện ⇒ chỉ hiện khi điều kiện đã giữ đủ 0,3 s — đẩy trang khỏi trang gốc tab không làm đĩa
///   lóe lên.
/// - **Nhấn giữ 0,4 s** (1.3.812): rung nhẹ, đĩa trượt (lò xo mềm) lên góc phải vùng header 5 giây
///   (`MediaDiscPlacement.elevatedFrame`) để bấm được nút đang bị che, rồi về chỗ. Trong lúc đó vẫn chạm mở sheet; đóng
///   sheet ⇒ về chỗ ngay; đổi màn ⇒ vẫn ở trên cho đủ 5 giây. Chỉ dời khung trong cửa sổ này, không đụng layout của app.
///   Cử chỉ nằm trong `MediaDiscFaceButton` (gọi `beginElevation`, 1.3.814) — **đừng** gắn lại `UILongPressGestureRecognizer`
///   lên `discView`: nút SwiftUI bên trong bắt chạm ngay lúc chạm xuống nên bộ nhận đó không bao giờ chạy.
/// - Lượt tính lại: neo đổi (`MediaDiscAnchorRegistry.onChange`), manager báo đổi trạng thái, xoay màn / đổi vùng an toàn,
///   và đồng hồ 0,4 s (`setPolling`, chế độ `.common` để chạy cả lúc đang cuộn) chỉ khi cửa sổ đang hiện.
/// - Giữ chỗ mép phải ở `FloatingWidgetLayoutCoordinator` (`.mediaDisc`) khi đĩa hiện: nút hub vừa thả / vừa hiện sẽ né
///   (đĩa không nhường — chỗ của nó do neo quyết).
@MainActor
final class MediaDiscContainerViewController: UIViewController {
    let discView = UIView()
    /// Đĩa đang hiện (không đang thu / đã ẩn) ⇒ cửa sổ nhận chạm trong khung đĩa.
    private(set) var isDiscInteractive = false

    private var discHost: UIHostingController<AnyView>?
    private var sheetHost: UIHostingController<AnyView>?
    private var pollTimer: Timer?
    private var isShowingDisc = false
    /// Chỗ ở `FloatingWidgetLayoutCoordinator` phải **mở** lại (chỉ `resolve` mở được; `refresh` chỉ cập nhật chỗ đã có).
    private var needsSlotClaim = true
    /// Lúc đĩa đang ẩn bắt đầu được phép hiện — hiện thật khi đã giữ đủ `showDelay`.
    private var pendingShowSince: Date?
    private var pendingShowWork: DispatchWorkItem?
    /// Đĩa tạm đứng ở header tới lúc này (nhấn giữ).
    private var elevatedUntil: Date?
    private var elevationWork: DispatchWorkItem?

    private enum Layout {
        static let pollInterval: TimeInterval = 0.4
        static let hiddenScale: CGFloat = 0.4
        /// Lệch dưới mức này coi như đứng yên (không chạy hiệu ứng mỗi lượt hỏi).
        static let moveTolerance: CGFloat = 0.5
        static let showDelay: TimeInterval = 0.3
        static let elevationDuration: TimeInterval = 5
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

        let size = MediaDiscPlacement.discSize
        discView.bounds = CGRect(x: 0, y: 0, width: size, height: size)
        discView.backgroundColor = .clear
        discView.isHidden = true
        view.addSubview(discView)

        let disc = makeHost(MediaDiscFaceButton(style: .corner) { [weak self] in
            self?.beginElevation()
        })
        addChild(disc)
        disc.view.frame = discView.bounds
        disc.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        discView.addSubview(disc.view)
        disc.didMove(toParent: self)
        discHost = disc

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
        cancelPendingShow()
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

    /// Tính lại chỗ + hiện/ẩn đĩa. `softSpring`: lò xo mềm của lượt lên / xuống header.
    func updateDisc(animated: Bool, softSpring: Bool = false) {
        guard isViewLoaded, view.bounds.width > 0, view.bounds.height > 0 else { return }
        guard let window = view.window, !window.isHidden else {
            cancelPendingShow()
            setDiscShown(false, frame: nil, animated: false)
            return
        }
        let placement = MediaDiscPlacement.resolve(bounds: view.bounds, safeInsets: view.safeAreaInsets)
        guard MediaDiscWindowManager.shared.isDiscAllowed, !placement.isBlocked else {
            cancelPendingShow()
            setDiscShown(false, frame: nil, animated: animated)
            return
        }
        if !isShowingDisc, !isShowDelayElapsed() { return }
        let frame = isElevated
            ? MediaDiscPlacement.elevatedFrame(bounds: view.bounds, safeInsets: view.safeAreaInsets)
            : placement.frame
        setDiscShown(true, frame: frame, animated: animated, softSpring: softSpring)
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

    // MARK: - Nhấn giữ ⇒ tạm lên header

    private var isElevated: Bool {
        guard let elevatedUntil else { return false }
        return elevatedUntil > Date()
    }

    /// Nhấn giữ đĩa góc (`MediaDiscFaceButton(.corner)` gọi) ⇒ đĩa lên header 5 giây; nhấn giữ lần nữa ⇒ tính lại 5 giây.
    func beginElevation() {
        guard isShowingDisc else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        AppLogger.shared.log("💿 [MediaDisc] Nhấn giữ ⇒ đĩa lên header 5 giây")
        elevationWork?.cancel()
        elevatedUntil = Date().addingTimeInterval(Layout.elevationDuration)
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.endElevation(animated: true)
            }
        }
        elevationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.elevationDuration, execute: work)
        updateDisc(animated: true, softSpring: true)
    }

    /// Hết 5 giây hoặc sheet điều khiển vừa đóng ⇒ đĩa về chỗ ở góc dưới.
    func endElevation(animated: Bool) {
        guard elevatedUntil != nil else { return }
        elevationWork?.cancel()
        elevationWork = nil
        elevatedUntil = nil
        updateDisc(animated: animated, softSpring: true)
    }

    // MARK: - Hiện / ẩn / dời

    private func setDiscShown(_ shown: Bool, frame: CGRect?, animated: Bool, softSpring: Bool = false) {
        if shown, let frame {
            let target = CGPoint(x: frame.midX, y: frame.midY)
            if !isShowingDisc {
                isShowingDisc = true
                discView.layer.removeAllAnimations()
                discView.center = target
                discView.transform = CGAffineTransform(scaleX: Layout.hiddenScale, y: Layout.hiddenScale)
                discView.isHidden = false
                animate(animated, motion: .spring) {
                    self.discView.transform = .identity
                }
            } else if hypot(discView.center.x - target.x, discView.center.y - target.y) > Layout.moveTolerance {
                animate(animated, motion: softSpring ? .softSpring : .spring) {
                    self.discView.center = target
                }
            }
            isDiscInteractive = true
            claimSlot(frame)
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

    private enum Motion {
        case spring
        /// Lên / xuống header khi nhấn giữ.
        case softSpring
        case collapse
    }

    private func animate(
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
        case .softSpring:
            duration = 0.6
            damping = 0.72
            curve = .curveEaseInOut
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
