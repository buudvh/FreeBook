import Combine
import SwiftUI
import UIKit

/// Root view controller của cửa sổ widget TTS khi chọn kiểu **Thanh nghe nhạc** (1.3.796). Cùng cửa sổ, cùng luật hiện/ẩn
/// với kiểu Đĩa nổi (`TTSFloatingWidgetWindowManager`); chỉ khác khung và cử chỉ:
/// - **Thanh** rộng hết bề ngang vùng an toàn trừ lề 8 pt (như thanh phát mini nghe nhạc), **cố định** ngay trên
///   `MainTabBar` — đúng chỗ thanh nghe nhạc đứng; nhạc và TTS không bao giờ cùng phát (1.3.791) nên không đè nhau. Không
///   kéo đổi chỗ được (1.3.799, anh Bửu: cố định vị trí); khoá vị trí cũ `ttsWidgetBarBottomGap` /
///   `ttsWidgetBarPillBottomGap` bỏ qua.
/// - **Viên thu gọn** nép sát mép phải vùng an toàn, ngang tâm thanh, cũng không kéo được.
/// - **Trong Reader** (1.3.806): thu gọn ⇒ viên ẩn (alpha 0, chạm xuyên), Reader hiện nút đĩa TTS; bung ⇒ thanh hạ sát đáy,
///   Reader chừa chỗ (`TTSWidgetBarPresence`).
/// - Vuốt thanh **ngang** quá 64 pt (hoặc vuốt nhanh) ⇒ thu gọn — cử chỉ duy nhất ở UIKit. Không có tap recognizer: chạm
///   nút / đĩa / chữ là nút SwiftUI.
/// - Mọi khung kẹp trong vùng an toàn; `widgetContainerView` = đúng khung thanh/viên ⇒ cửa sổ chỉ nhận chạm trong đó.
///
/// Giữ chỗ với widget nổi khác (`FloatingWidgetLayoutCoordinator`): viên giữ chỗ mép phải (không dời); thanh rộng cả hai
/// mép nên không giữ chỗ (gỡ `.tts`). Nút hub tự né chỗ của viên khi nó được thả / hiện ra.
@MainActor
final class TTSWidgetBarContainerViewController: UIViewController, UIGestureRecognizerDelegate,
    TTSFloatingWidgetContaining {
    let widgetContainerView = UIView()

    private let model = TTSWidgetBarViewModel()
    private var hostingController: UIHostingController<AnyView>?
    private var panGesture: UIPanGestureRecognizer?
    private var panStartCenter: CGPoint = .zero
    /// Viên cần **mở** chỗ ở `FloatingWidgetLayoutCoordinator` (chỉ `resolve` mở được; `refresh` chỉ cập nhật chỗ đã có):
    /// lúc mới dựng, lúc widget hiện lại (window manager đã gỡ chỗ khi ẩn), lúc vừa thu gọn.
    private var needsSlotClaim = true
    private var cancellables = Set<AnyCancellable>()

    private enum Layout {
        static let sideMargin: CGFloat = 8
        /// Khe giữa thanh và `MainTabBar` — bằng khe dưới của `AudioMiniPlayerBar`.
        static let tabBarGap: CGFloat = 6
        /// Lề tối thiểu tới mép trên / dưới vùng an toàn (màn ngang quá thấp thì kẹp).
        static let edgeMargin: CGFloat = 4
        static let collapseSwipeDistance: CGFloat = 64
        static let collapseSwipeVelocity: CGFloat = 700
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        view.addSubview(widgetContainerView)

        // Cửa sổ riêng không thừa hưởng `.tint` của `MainTabView` ⇒ gắn màu nhấn ở gốc (vạch tiến độ, sheet Hẹn giờ).
        let content = TTSWidgetBarContentView(model: model, rotationState: TTSWidgetCoverRotation.shared.state)
            .appAccentTint()
        let rootView: AnyView
        if let container = TTSFloatingWidgetWindowManager.shared.modelContainer {
            rootView = AnyView(content.modelContainer(container))
        } else {
            rootView = AnyView(content)
        }
        let hosting = UIHostingController(rootView: rootView)
        hosting.view.backgroundColor = .clear
        // Khung đã tự kẹp trong vùng an toàn: không để SwiftUI chèn thêm lề an toàn khi thanh chạm mép / tai thỏ.
        hosting.safeAreaRegions = []
        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        hostingController = hosting

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(pan)
        panGesture = pan

        // `@Published` phát ở willSet ⇒ đặt khung ở lượt sau, lúc `isCollapsed` / `isReaderVisible` đã là giá trị mới.
        Publishers.CombineLatest(model.$isCollapsed.removeDuplicates(), model.$isReaderVisible.removeDuplicates())
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.model.isDragging else { return }
                self.updateLayoutForCurrentMode(animated: true)
            }
            .store(in: &cancellables)

        updateLayoutForCurrentMode(animated: false)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !model.isDragging {
            updateLayoutForCurrentMode(animated: false)
        }
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        view.setNeedsLayout()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateLayoutForCurrentMode(animated: false)
        }
    }

    // MARK: - TTSFloatingWidgetContaining

    /// Window manager gọi lúc widget chuyển từ ẩn sang hiện. Thanh không nhường chỗ cho widget khác (nó đứng yên, nút hub
    /// tự né) ⇒ không xếp lại; chỉ đếm lại "Tự thu gọn sau 5 giây" (lần dừng trước đã huỷ bộ đếm).
    func requestPlacementResolve() {
        needsSlotClaim = true
        model.noteInteraction()
    }

    func reveal(animated: Bool) {
        model.revealRequested()
        updateLayoutForCurrentMode(animated: animated)
    }

    func updateLayoutForCurrentMode(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let frame = restingFrame()
        let hidesPill = hidesPillInReader
        registerSlot(frame: frame, hidesPill: hidesPill)

        let applyLayout = {
            self.widgetContainerView.bounds = CGRect(origin: .zero, size: frame.size)
            self.widgetContainerView.center = CGPoint(x: frame.midX, y: frame.midY)
            self.hostingController?.view.frame = self.widgetContainerView.bounds
            // Alpha 0 ⇒ `FloatingWidgetUIWindow.hitTest` trả nil: chạm xuyên xuống Reader.
            self.widgetContainerView.alpha = hidesPill ? 0 : 1
            self.view.layoutIfNeeded()
        }

        if animated {
            UIView.animate(
                withDuration: 0.34,
                delay: 0,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0,
                options: [.allowUserInteraction, .beginFromCurrentState, .curveEaseOut],
                animations: applyLayout,
                completion: nil
            )
        } else {
            applyLayout()
        }
    }

    // MARK: - Khung

    private var currentHeight: CGFloat {
        model.isCollapsed ? TTSWidgetBarPillView.height : MiniPlayerBarChrome.height
    }

    /// Thu gọn trong Reader (1.3.806): không hiện viên — Reader có nút đĩa TTS trên nút tai nghe (`ReaderTTSDiscButton`).
    private var hidesPillInReader: Bool {
        model.isCollapsed && model.isReaderVisible
    }

    /// Khoảng từ mép dưới widget tới mép dưới vùng an toàn — **cố định**: thanh ngay trên `MainTabBar` như
    /// `AudioMiniPlayerBar` (khe 6 pt), viên ngang tâm thanh. Trong Reader (không có thanh tab) thanh bung nằm **sát đáy**,
    /// thấp hơn nút tai nghe; Reader chừa chỗ theo `TTSWidgetBarPresence.readerBottomInset` nên không che chữ.
    private var fixedBottomGap: CGFloat {
        if model.isReaderVisible, !model.isCollapsed {
            return TTSWidgetBarPresence.readerBarBottomGap
        }
        let barGap = MainTabBar.barHeight + Layout.tabBarGap
        guard model.isCollapsed else { return barGap }
        return barGap + (MiniPlayerBarChrome.height - TTSWidgetBarPillView.height) / 2
    }

    /// Khoảng đáy hợp lệ để widget cao `height` nằm trọn trong vùng an toàn (chừa `edgeMargin` hai đầu).
    private func bottomGapRange(height: CGFloat) -> ClosedRange<CGFloat> {
        let insets = view.safeAreaInsets
        let usable = view.bounds.height - insets.top - insets.bottom
        let maxGap = max(Layout.edgeMargin, usable - height - Layout.edgeMargin)
        return Layout.edgeMargin...maxGap
    }

    private func clampedBottomGap(_ gap: CGFloat, height: CGFloat) -> CGFloat {
        let range = bottomGapRange(height: height)
        return min(max(gap, range.lowerBound), range.upperBound)
    }

    /// Tâm Y ứng với khoảng đáy `gap` (theo toạ độ `view`).
    private func centerY(forBottomGap gap: CGFloat, height: CGFloat) -> CGFloat {
        view.bounds.height - view.safeAreaInsets.bottom - gap - height / 2
    }

    private func restingFrame() -> CGRect {
        let bounds = view.bounds
        let insets = view.safeAreaInsets
        let height = currentHeight
        let gap = clampedBottomGap(fixedBottomGap, height: height)
        let originY = centerY(forBottomGap: gap, height: height) - height / 2

        if model.isCollapsed {
            let width = TTSWidgetBarPillView.width
            return CGRect(x: bounds.width - insets.right - width, y: originY, width: width, height: height)
        }
        let width = max(0, bounds.width - insets.left - insets.right - Layout.sideMargin * 2)
        return CGRect(x: insets.left + Layout.sideMargin, y: originY, width: width, height: height)
    }

    /// Viên giữ chỗ mép phải; thanh gỡ chỗ. Cửa sổ đang ẩn (TTS dừng) thì không mở chỗ — cờ Reader vẫn có thể đổi dạng
    /// lúc đó, nút hub không được né một viên không có trên màn.
    private func registerSlot(frame: CGRect, hidesPill: Bool) {
        let coordinator = FloatingWidgetLayoutCoordinator.shared
        // Viên đang ẩn (trong Reader) không giữ chỗ — nút hub không né một viên không có trên màn.
        guard model.isCollapsed, !hidesPill else {
            coordinator.unregister(.tts)
            needsSlotClaim = true
            return
        }
        guard let window = view.window, !window.isHidden else { return }
        if needsSlotClaim {
            needsSlotClaim = false
            // Viên không nhường (chỗ cố định): khoảng tìm chỉ một điểm ⇒ `resolve` chỉ để mở chỗ,
            // cạnh / tâm thật ghi lại ngay bằng `refresh` bên dưới.
            _ = coordinator.resolve(
                id: .tts,
                edge: .right,
                proposedCenterY: frame.midY,
                height: frame.height,
                minY: frame.midY,
                maxY: frame.midY
            )
        }
        coordinator.refresh(id: .tts, edge: .right, centerY: frame.midY, height: frame.height)
    }

    // MARK: - Cử chỉ

    /// Vuốt thanh sang ngang: thanh đi theo tay theo chiều ngang (không đổi độ cao); thả quá ngưỡng ⇒ thu gọn, chưa tới ⇒
    /// trượt về chỗ cũ.
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        switch gesture.state {
        case .began:
            panStartCenter = widgetContainerView.center
            model.beginDrag()
        case .changed:
            let translation = gesture.translation(in: view)
            widgetContainerView.center = CGPoint(x: panStartCenter.x + translation.x, y: panStartCenter.y)
        case .ended, .cancelled, .failed:
            model.endDrag()
            let translation = gesture.translation(in: view).x
            let velocity = gesture.velocity(in: view).x
            if gesture.state == .ended,
               abs(translation) > Layout.collapseSwipeDistance || abs(velocity) > Layout.collapseSwipeVelocity {
                model.collapseByUser()
            }
            updateLayoutForCurrentMode(animated: true)
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    /// Chỉ vuốt **ngang** trên thanh đang bung mới bắt đầu (vị trí cố định — không kéo dọc); viên thu gọn không có cử chỉ.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === panGesture,
              let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        guard !model.isCollapsed else { return false }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
