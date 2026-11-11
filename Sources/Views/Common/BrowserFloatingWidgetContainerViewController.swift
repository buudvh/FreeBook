import Combine
import SwiftUI
import UIKit

/// View controller của widget trình duyệt thu nhỏ (dựng lại ở 1.3.533 sau khi tách khỏi hub nổi): sở hữu
/// `UIPanGestureRecognizer` / `UITapGestureRecognizer` và cập nhật frame trực tiếp trên `UIView`, đúng kiến
/// trúc nút hub — ngón tay không bị trễ theo vòng cập nhật state của SwiftUI.
///
/// ## Nửa viên thuốc dính mép (anh Bửu duyệt mockup 2026-11-11)
/// Nút là nửa viên 38 × 36 **luôn dính mép** trái / phải (`EdgePillShape`), không còn nép mép nửa ẩn / bung / tự thu,
/// cũng không còn mờ 0,7 cố định khi nghỉ (icon nay mờ theo Độ trong suốt của nút nổi, trong `VisibleBrowserReopenButton`).
/// Bắt đầu kéo ⇒ co thành hình tròn 36 đặt đúng tâm icon, theo tay; thả ⇒ bám mép gần hơn, né widget nổi khác, lưu chỗ.
///
/// Chạm là mở lại trình duyệt (`VisibleBrowserTabManager.reopenContainer()`).
@MainActor
final class BrowserFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    let widgetContainerView = UIView()

    private let viewModel = VisibleBrowserReopenViewModel()
    private let presentationReader: VisibleBrowserPresentationReader
    private var hostingController: UIHostingController<VisibleBrowserReopenButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()
    private var tabCount = 0

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    /// Lượt layout hợp lệ kế tiếp phải xếp lại để né widget nổi khác (`FloatingWidgetLayoutCoordinator`). Bật sẵn
    /// cho lần tạo cửa sổ đầu; `prepareForAppearance()` bật lại mỗi lần widget hiện lại.
    private var needsPlacementResolve = true

    enum Layout {
        /// Nửa viên lúc dính mép.
        static let size: CGSize = VisibleBrowserReopenButton.size
        static let height: CGFloat = VisibleBrowserReopenButton.size.height
        /// Hình tròn lúc đang kéo.
        static let dragDiameter: CGFloat = VisibleBrowserReopenButton.dragDiameter
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
            edge: viewModel.isDragging ? nil : viewModel.edgeDirection,
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

        // Mép đổi / bắt đầu – thôi kéo ⇒ nút vẽ lại hình (nửa viên đúng mép hoặc hình tròn).
        Publishers.CombineLatest(viewModel.$edgeDirection.removeDuplicates(), viewModel.$isDragging.removeDuplicates())
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

    // MARK: - Hiện lại

    /// Đưa widget về trạng thái xuất hiện chuẩn (không kéo dở). Window manager gọi mỗi lần widget hiện lại sau khi bị
    /// ẩn — kể cả khi bị ẩn giữa lúc đang kéo (ẩn cửa sổ thì không còn sự kiện `.ended` nào về).
    func prepareForAppearance() {
        viewModel.prepareForAppearance()
        needsPlacementResolve = true
        updateLayout(animated: false)
    }

    // MARK: - Layout

    /// Kẹp trong vùng đứng cố định `EdgePillZone` (1.3.867): dưới vùng header, trên vùng nút "+" / thanh tab — kể cả màn
    /// không có chúng, để nút không nhảy khi đổi màn.
    private func clampedY(_ value: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: Layout.height,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + EdgePillZone.topClearance,
            bottomMargin: view.safeAreaInsets.bottom + EdgePillZone.bottomClearance
        )
    }

    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, screenHeight: bounds.height)
        let halfWidth = Layout.size.width / 2
        let x = viewModel.edgeDirection == .left ? halfWidth : bounds.width - halfWidth
        return CGPoint(x: x, y: y)
    }

    /// Vẽ lại vị trí dính mép. `internal` để window manager gọi được.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        // Chỉ xếp lại khi đã nằm trong cửa sổ (bounds thật) và không đang kéo — thả tay tự xếp ở `handlePan`.
        if needsPlacementResolve, view.window != nil, !viewModel.isDragging {
            resolvePlacement()
        }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = Layout.size
        // Báo lại khung nghỉ (xoay màn, đổi vùng an toàn) — không xếp lại; widget đang ẩn thì coordinator bỏ qua.
        FloatingWidgetLayoutCoordinator.shared.refresh(
            id: .browser,
            edge: viewModel.edgeDirection,
            centerY: targetCenter.y,
            height: Layout.height
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
            widgetHeight: Layout.height,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + EdgePillZone.topClearance,
            bottomMargin: view.safeAreaInsets.bottom + EdgePillZone.bottomClearance
        )
        let proposed = clampedY(viewModel.verticalRatio * screenHeight, screenHeight: screenHeight)
        let placement = FloatingWidgetLayoutCoordinator.shared.resolve(
            id: .browser,
            edge: viewModel.edgeDirection,
            proposedCenterY: proposed,
            height: Layout.height,
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
            // Co thành hình tròn đặt đúng tâm icon (tâm đầu bo) ⇒ không giật dưới tay.
            let frame = widgetContainerView.frame
            let radius = Layout.height / 2
            let iconX = viewModel.edgeDirection == .left ? frame.maxX - radius : frame.minX + radius
            let start = CGPoint(x: iconX, y: frame.midY)
            panStartCenter = start
            viewModel.handleDragStart()
            let diameter = Layout.dragDiameter
            UIView.animate(withDuration: 0.15, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                self.widgetContainerView.bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
                self.widgetContainerView.center = start
                self.hostingController?.view.frame = self.widgetContainerView.bounds
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let half = Layout.dragDiameter / 2
            let rawX = min(max(panStartCenter.x + translation.x, half), container.bounds.width - half)
            let rawY = panStartCenter.y + translation.y
            widgetContainerView.center = CGPoint(
                x: rawX,
                y: clampedY(rawY, screenHeight: container.bounds.height)
            )
        case .ended, .cancelled, .failed:
            guard viewModel.isDragging else { return }
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetHeight: Layout.height,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + EdgePillZone.topClearance,
                bottomMargin: view.safeAreaInsets.bottom + EdgePillZone.bottomClearance
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
