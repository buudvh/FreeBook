import Combine
import SwiftUI
import UIKit

/// View controller của **nút hub nổi** (1.3.524): sở hữu cử chỉ kéo/chạm và cập nhật frame trực tiếp trên
/// `UIView`. Menu nằm ở `+Menu.swift`; hành động mở mục, nút của dòng Video và sheet Thông báo ở
/// `+Actions.swift`; giữ chỗ với widget nổi khác ở `+Placement.swift`.
///
/// Kéo/thả bằng UIKit (không phải cử chỉ SwiftUI): ngón tay không bị trễ theo vòng cập nhật state.
///
/// ## Nửa viên thuốc dính mép (anh Bửu duyệt mockup 2026-11-11)
/// Nút là nửa viên 38 × 36 **luôn dính mép** trái / phải (`EdgePillShape`), không còn nép mép nửa ẩn / bung / tự thu.
/// Bắt đầu kéo ⇒ co thành hình tròn 36 đặt đúng tâm icon, theo tay; thả ⇒ bám mép gần hơn, né widget nổi khác
/// (`+Placement.swift`), lưu chỗ.
///
/// ## Cây view (từ dưới lên)
/// 1. `menuBackdropView` — phủ toàn màn, trong suốt, chỉ hiện khi menu mở; chạm vào là đóng menu.
/// 2. `widgetContainerView` — nút hub.
/// 3. `menuContainerView` — thẻ menu, cạnh nút về phía xa mép.
///
/// ## Bảng chạm (cài đặt "Khi chạm hub", `FloatingHubTapBehavior`)
/// Menu đang mở ⇒ đóng. Còn lại do `activateByRunningTasks` (`+Actions.swift`) quyết. **Luôn hiện tất cả mục** (mặc
/// định, 2026-11-06): mở menu ở trang chính.
/// **Mở thẳng khi chỉ có 1 tác vụ** (bảng chốt 2026-10-22) rẽ theo **số tiến trình** của snapshot lúc chạm: 0 ⇒ mở
/// màn Thông báo; 1 ⇒ mở thẳng mục đó (AI ⇒ menu ở trang "Tác vụ AI"); từ 2 ⇒ mở menu.
@MainActor
final class FloatingHubContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    /// `internal` (không `private`): file `+Actions`/`+Menu` cần dùng, mà `private` của Swift chỉ có hiệu lực
    /// trong một file — lỗi kiểu này đã làm CI 1.3.445 đỏ.
    let viewModel = FloatingHubViewModel()
    let presentationReader: FloatingHubPresentationReader

    let menuBackdropView = UIView()
    let widgetContainerView = UIView()
    let menuContainerView = UIView()
    /// `internal`: `+Menu.swift` tạo nó ở lần mở menu đầu tiên.
    var menuHostingController: UIHostingController<FloatingHubMenuView>?
    /// Trang đang hiện của thẻ menu (1.3.558): ba dòng chính, hoặc danh sách truyện đang chạy AI. Mở menu luôn về `.main`.
    var menuPage: FloatingHubMenuView.Page = .main

    private var buttonHostingController: UIHostingController<FloatingHubButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!
    /// Lượt layout hợp lệ kế tiếp phải xếp lại để né widget nổi khác (`+Placement.swift`). Bật sẵn cho lần tạo cửa
    /// sổ đầu; `prepareForAppearance()` bật lại mỗi lần hub hiện lại. `internal` vì `+Placement.swift` hạ cờ.
    var needsPlacementResolve = true

    enum Layout {
        /// Nửa viên lúc dính mép.
        static let size: CGSize = FloatingHubButton.size
        static let height: CGFloat = FloatingHubButton.size.height
        /// Hình tròn lúc đang kéo.
        static let dragDiameter: CGFloat = FloatingHubButton.dragDiameter
        /// Lề ngang của thẻ menu với mép màn.
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 12
        /// Khoảng cách giữa nút và thẻ menu.
        static let menuSpacing: CGFloat = 8
        static let menuAnimationDuration: TimeInterval = 0.18
    }

    /// Cửa sổ đọc cờ này trong `hitTest`.
    var isMenuOpen: Bool { viewModel.isMenuOpen }

    init(presentationReader: FloatingHubPresentationReader) {
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

        menuBackdropView.backgroundColor = .clear
        menuBackdropView.isHidden = true
        menuBackdropView.frame = view.bounds
        menuBackdropView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let backdropTap = UITapGestureRecognizer(target: self, action: #selector(handleBackdropTap(_:)))
        menuBackdropView.addGestureRecognizer(backdropTap)
        view.addSubview(menuBackdropView)

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        menuContainerView.backgroundColor = .clear
        menuContainerView.clipsToBounds = false
        menuContainerView.layer.masksToBounds = false
        menuContainerView.isHidden = true
        view.addSubview(menuContainerView)

        let hosting = UIHostingController(rootView: makeButton())
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.buttonHostingController = hosting

        setupGestures()
        bindState()
        updateLayout(animated: false)
    }

    private func makeButton() -> FloatingHubButton {
        FloatingHubButton(
            state: presentationReader.snapshot.button,
            edge: viewModel.isDragging ? nil : viewModel.edgeDirection,
            onActivate: { [weak self] in
                self?.handlePrimaryAction()
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
        // Nút chỉ vẽ lại khi tập tiến trình hoặc số chưa đọc đổi — tiêu đề AI đổi theo batch không chạm tới đây.
        // Hình nút (nửa viên theo mép / tròn lúc kéo) vẽ lại ở sink `edgeDirection` + `isDragging` bên dưới.
        presentationReader.$snapshot
            .map(\.button)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshButton()
            }
            .store(in: &cancellables)

        // Menu chỉ vẽ khi đang mở, và chỉ **cập nhật** dòng đã có (sáng/xám, badge, chữ) — tập dòng cố định nên
        // không bao giờ phải đóng menu vì "hết mục". Danh sách truyện đang chạy AI cũng vẽ lại thẻ (trang "Tác vụ AI").
        presentationReader.$snapshot
            .map { ($0.items, $0.aiTasks, $0.sourceChecks) }
            .removeDuplicates(by: ==)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.isMenuOpen else { return }
                self.refreshMenu()
                self.layoutMenu()
            }
            .store(in: &cancellables)

        // Mép đổi / bắt đầu – thôi kéo ⇒ nút vẽ lại hình (nửa viên đúng mép hoặc hình tròn).
        Publishers.CombineLatest(viewModel.$edgeDirection.removeDuplicates(), viewModel.$isDragging.removeDuplicates())
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshButton()
            }
            .store(in: &cancellables)
    }

    private func refreshButton() {
        buttonHostingController?.rootView = makeButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        menuBackdropView.frame = view.bounds
        if !viewModel.isDragging {
            updateLayout(animated: false)
            layoutMenu()
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateLayout(animated: false)
            self?.layoutMenu()
        }
    }

    // MARK: - Layout nút

    /// Kẹp tâm Y trong vùng an toàn — nút (và thẻ menu) không bao giờ chui vào thanh trạng thái hay thanh tab.
    /// `internal` vì `+Menu.swift` dùng cho thẻ menu.
    func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: height,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
    }

    /// Tâm nửa viên dính mép đã nhớ (cạnh phẳng áp sát mép màn).
    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, height: Layout.height, screenHeight: bounds.height)
        let halfWidth = Layout.size.width / 2
        let x = viewModel.edgeDirection == .left ? halfWidth : bounds.width - halfWidth
        return CGPoint(x: x, y: y)
    }

    /// Vẽ lại vị trí dính mép. `internal` để window manager và file `+Actions` gọi được.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        // Chỉ xếp lại khi đã nằm trong cửa sổ (bounds thật) và không đang kéo — thả tay tự xếp ở `handlePan`.
        if needsPlacementResolve, view.window != nil, !viewModel.isDragging {
            resolvePlacement()
        }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = Layout.size
        refreshPlacementSlot(centerY: targetCenter.y)

        let applyLayout = {
            self.widgetContainerView.bounds = CGRect(origin: .zero, size: targetSize)
            self.widgetContainerView.center = targetCenter
            self.buttonHostingController?.view.frame = self.widgetContainerView.bounds
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

    /// Đưa hub về trạng thái xuất hiện chuẩn — menu đóng. Window manager gọi mỗi lần hub hiện lại sau khi bị ẩn (cả
    /// cửa sổ hoặc chỉ nút).
    func prepareForAppearance() {
        closeMenu(animated: false)
        viewModel.prepareForAppearance()
        needsPlacementResolve = true
        updateLayout(animated: false)
    }

    // MARK: - Cử chỉ

    /// Hành động chính của hub — đường chung cho chạm và VoiceOver (`FloatingHubButton.onActivate`).
    func handlePrimaryAction() {
        guard !viewModel.isDragging else { return }

        if viewModel.isMenuOpen {
            closeMenu(animated: true)
            return
        }
        activateByRunningTasks()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handlePrimaryAction()
    }

    @objc private func handleBackdropTap(_ gesture: UITapGestureRecognizer) {
        // Chạm ngoài thẻ chỉ đóng menu (chạm bị nuốt, kiểu popover).
        closeMenu(animated: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            // Hạ cờ menu trước tiên: đang kéo mà lớp nền còn sống là nuốt chạm của cả app.
            closeMenu(animated: false)
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
                self.buttonHostingController?.view.frame = self.widgetContainerView.bounds
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let half = Layout.dragDiameter / 2
            let rawX = min(max(panStartCenter.x + translation.x, half), container.bounds.width - half)
            let rawY = panStartCenter.y + translation.y
            widgetContainerView.center = CGPoint(
                x: rawX,
                y: clampedY(rawY, height: Layout.dragDiameter, screenHeight: container.bounds.height)
            )
        case .ended, .cancelled, .failed:
            guard viewModel.isDragging else { return }
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetHeight: Layout.height,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
                bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
            )
            resolvePlacement()
            updateLayout(animated: true)
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        return false
    }
}
