import Combine
import SwiftUI
import UIKit

/// View controller của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533 sau khi tách khỏi hub nổi): sở hữu
/// `UIPanGestureRecognizer` / `UITapGestureRecognizer` và cập nhật frame trực tiếp trên `UIView`, đúng kiến
/// trúc hub và widget TTS — ngón tay không bị trễ theo vòng cập nhật state của SwiftUI.
///
/// ## Một cỡ, hai vị trí
/// Nút tròn **36px**: `.peeking` là nút **ngậm vào mép** (tâm nằm đúng trên mép nên một nửa ra ngoài),
/// `.revealed` là nút nằm trong màn với lề ngang nhỏ. Animation thu/bung chỉ là **dịch chuyển**.
///
/// ## Trong suốt hơn
/// Hosting view của nút mờ **0,7** khi nghỉ, đậm **1,0** khi đang chạm hoặc kéo (`setTouchActive`, do
/// `BrowserFloatingWidgetUIWindow.sendEvent` báo). Chỉ hạ alpha trên **hosting view**, không bao giờ trên
/// `widgetContainerView` hay cửa sổ — `hitTest` của cửa sổ có guard `alpha > 0.01` trên `widgetContainerView`.
///
/// Chạm ở cả hai trạng thái là mở lại trình duyệt (`VisibleBrowserTabManager.reopenContainer()`).
@MainActor
final class BrowserFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    let widgetContainerView = UIView()

    private let viewModel = VisibleBrowserReopenViewModel()
    private let presentationReader: VisibleBrowserPresentationReader
    private var hostingController: UIHostingController<VisibleBrowserReopenButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()
    private var tabCount = 0
    private var isTouchActive = false

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    /// Lượt layout hợp lệ kế tiếp phải xếp lại để né widget nổi khác (`FloatingWidgetLayoutCoordinator`). Bật sẵn
    /// cho lần tạo cửa sổ đầu; `prepareForAppearance()` bật lại mỗi lần widget hiện lại.
    private var needsPlacementResolve = true

    enum Layout {
        static let size: CGFloat = VisibleBrowserReopenButton.size
        /// Lề ngang khi nút ở dạng bung — nhỏ, vì nút vốn đã nhỏ.
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 12
        /// Thả trong khoảng này tính là "dán mép" ⇒ thu gọn.
        static let edgeSnapDistance: CGFloat = 26
        /// Alpha của hosting view khi nghỉ / khi đang chạm-kéo.
        static let restingContentAlpha: CGFloat = 0.7
        static let activeContentAlpha: CGFloat = 1.0
        static let alphaAnimationDuration: TimeInterval = 0.15
    }

    init(presentationReader: VisibleBrowserPresentationReader) {
        self.presentationReader = presentationReader
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        tabCount = presentationReader.snapshot.tabCount
        let hosting = UIHostingController(rootView: makeButton())
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false
        hosting.view.alpha = Layout.restingContentAlpha

        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hostingController = hosting

        setupGestures()
        bindState()
        updateLayout(animated: false)
    }

    private func makeButton() -> VisibleBrowserReopenButton {
        VisibleBrowserReopenButton(
            tabCount: tabCount,
            mode: viewModel.mode,
            edge: viewModel.edgeDirection,
            onActivate: { [weak self] in
                self?.reopenBrowser()
            }
        )
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(panGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(tapGesture)
    }

    private func bindState() {
        presentationReader.$snapshot
            .map(\.tabCount)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                guard let self, count != self.tabCount else { return }
                self.tabCount = count
                self.refreshContent()
            }
            .store(in: &cancellables)

        // Nút phải vẽ lại khi bung/thu: badge đổi giữa **số tab** và **chấm đỏ**.
        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshContent()
                if !self.viewModel.isDragging {
                    self.updateLayout(animated: true)
                }
            }
            .store(in: &cancellables)

        // Badge đổi phía theo mép ⇒ chỉ vẽ lại khi cạnh đổi (chỉ xảy ra lúc nhả tay).
        viewModel.$edgeDirection
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshContent()
            }
            .store(in: &cancellables)
    }

    private func refreshContent() {
        hostingController?.rootView = makeButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !viewModel.isDragging {
            updateLayout(animated: false)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateLayout(animated: false)
        }
    }

    // MARK: - Hiện lại & độ trong suốt

    /// Đưa widget về trạng thái xuất hiện chuẩn: nép mép, mờ 0,7. Window manager gọi mỗi lần widget hiện lại
    /// sau khi bị ẩn — kể cả khi bị ẩn giữa lúc đang chạm (ẩn cửa sổ thì không còn sự kiện `.ended` nào về).
    func prepareForAppearance() {
        viewModel.prepareForAppearance()
        setTouchActive(false, animated: false)
        needsPlacementResolve = true
        updateLayout(animated: false)
    }

    /// Đậm khi đang chạm/kéo, mờ khi nghỉ. Idempotent — `sendEvent` gọi ở mọi sự kiện chạm.
    func setTouchActive(_ active: Bool, animated: Bool = true) {
        guard isTouchActive != active || !animated else { return }
        isTouchActive = active
        let targetAlpha = active ? Layout.activeContentAlpha : Layout.restingContentAlpha
        let apply: () -> Void = { self.hostingController?.view.alpha = targetAlpha }
        guard animated else {
            apply()
            return
        }
        UIView.animate(
            withDuration: Layout.alphaAnimationDuration,
            delay: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
            animations: apply,
            completion: nil
        )
    }

    // MARK: - Layout

    /// Kẹp theo safe area để widget không bao giờ ra ngoài vùng hiển thị hợp lệ.
    private func clampedY(_ value: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: Layout.size,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
    }

    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, screenHeight: bounds.height)

        if viewModel.mode == .peeking {
            // Tâm nằm **đúng trên mép** ⇒ một nửa nút ra ngoài, đúng dáng "cất vào mép".
            let x = viewModel.edgeDirection == .left ? 0 : bounds.width
            return CGPoint(x: x, y: y)
        }

        let x = FloatingWidgetGeometry.restingCenterX(
            edge: viewModel.edgeDirection,
            widgetWidth: Layout.size,
            screenWidth: bounds.width,
            horizontalMargin: Layout.horizontalMargin
        )
        return CGPoint(x: x, y: y)
    }

    /// Vẽ lại vị trí theo `mode` hiện tại. `internal` để window manager gọi được.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        // Chỉ xếp lại khi đã nằm trong cửa sổ (bounds thật) và không đang kéo — thả tay tự xếp ở `handlePan`.
        if needsPlacementResolve, view.window != nil, !viewModel.isDragging {
            resolvePlacement()
        }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = CGSize(width: Layout.size, height: Layout.size)
        // Báo lại khung nghỉ (xoay màn, đổi vùng an toàn) — không xếp lại; widget đang ẩn thì coordinator bỏ qua.
        FloatingWidgetLayoutCoordinator.shared.refresh(
            id: .browser,
            edge: viewModel.edgeDirection,
            centerY: targetCenter.y,
            height: Layout.size
        )

        let applyLayout = {
            self.widgetContainerView.bounds = CGRect(origin: .zero, size: targetSize)
            self.widgetContainerView.center = targetCenter
            self.hostingController?.view.frame = self.widgetContainerView.bounds
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

    /// Né widget nổi khác cùng mép (`FloatingWidgetLayoutCoordinator`) — widget này là bên nhường. Dời thì lưu như
    /// khi kéo tay; khung mới do lượt `updateLayout` kế tiếp đặt (có hiệu ứng khi vừa thả tay).
    private func resolvePlacement() {
        needsPlacementResolve = false
        let screenHeight = view.bounds.height
        guard view.bounds.width > 0, screenHeight > 0 else { return }

        let range = FloatingWidgetGeometry.centerYRange(
            widgetHeight: Layout.size,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
        let proposed = clampedY(viewModel.verticalRatio * screenHeight, screenHeight: screenHeight)
        let placement = FloatingWidgetLayoutCoordinator.shared.resolve(
            id: .browser,
            edge: viewModel.edgeDirection,
            proposedCenterY: proposed,
            height: Layout.size,
            minY: range.lowerBound,
            maxY: range.upperBound
        )
        guard placement.isMoved(from: viewModel.edgeDirection, centerY: proposed) else { return }
        viewModel.applyResolvedPlacement(edge: placement.edge, centerY: placement.centerY, screenHeight: screenHeight)
    }

    // MARK: - Cử chỉ

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            viewModel.handleDragStart()
            panStartCenter = widgetContainerView.center
            // Kéo từ trạng thái thu gọn là bung ra ngay: kéo một nửa nút đang ngậm mép là thao tác khó.
            if viewModel.mode == .peeking {
                viewModel.reveal()
                updateLayout(animated: true)
                panStartCenter = widgetContainerView.center
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let rawX = panStartCenter.x + translation.x
            let rawY = panStartCenter.y + translation.y
            widgetContainerView.center = CGPoint(
                x: rawX,
                y: clampedY(rawY, screenHeight: container.bounds.height)
            )
        case .ended, .cancelled:
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetSize: Layout.size,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
                bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin,
                edgeSnapDistance: Layout.edgeSnapDistance
            )
            resolvePlacement()
            updateLayout(animated: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        reopenBrowser()
    }

    /// Đường chung cho chạm và VoiceOver. Mở lại thành công thì trình duyệt thôi "thu nhỏ" ⇒ window manager
    /// tự ẩn widget qua `stateDidChangeNotification`; lần hiện sau đi qua `prepareForAppearance()`.
    private func reopenBrowser() {
        guard !viewModel.isDragging else { return }
        VisibleBrowserTabManager.shared.reopenContainer()
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
