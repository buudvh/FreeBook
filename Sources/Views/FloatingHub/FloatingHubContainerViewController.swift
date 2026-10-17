import Combine
import SwiftUI
import UIKit

/// View controller của **nút hub nổi** (1.3.524): sở hữu cử chỉ kéo/chạm và cập nhật frame trực tiếp trên
/// `UIView`. Menu nằm ở `+Menu.swift`; hành động mở mục, nút của dòng Video và sheet Thông báo ở
/// `+Actions.swift`.
///
/// Kéo/thả bằng UIKit (không phải cử chỉ SwiftUI) đúng như widget TTS: ngón tay không bị trễ theo vòng cập
/// nhật state.
///
/// ## Một cỡ, hai vị trí
/// Nút 36px ở cả hai trạng thái: `.peeking` là nút **ngậm vào mép** (tâm nằm đúng trên mép nên một nửa ra
/// ngoài), `.revealed` là nút nằm trong màn với lề ngang 8pt. Animation thu/bung chỉ là dịch chuyển.
///
/// ## Cây view (từ dưới lên)
/// 1. `menuBackdropView` — phủ toàn màn, trong suốt, chỉ hiện khi menu mở; chạm vào là đóng menu.
/// 2. `widgetContainerView` — nút hub.
/// 3. `menuContainerView` — thẻ menu, cạnh nút về phía xa mép.
///
/// ## Bảng chạm (1.3.533)
/// Menu luôn có đủ ba dòng nên chạm **không còn phụ thuộc số mục**: `.peeking` ⇒ bung **và** mở menu ngay;
/// `.revealed` ⇒ mở menu; menu đang mở ⇒ đóng. Không còn nhánh "1 mục thì mở thẳng".
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

    private var buttonHostingController: UIHostingController<FloatingHubButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    enum Layout {
        static let size: CGFloat = FloatingHubButton.size
        /// Lề ngang khi nút ở dạng bung — nhỏ, vì nút vốn đã nhỏ.
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 12
        /// Thả trong khoảng này tính là "dán mép" ⇒ thu gọn.
        static let edgeSnapDistance: CGFloat = 26
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
            mode: viewModel.mode,
            edge: viewModel.edgeDirection,
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
        // Nút chỉ vẽ lại khi tập mục đang hoạt động hoặc số chưa đọc đổi — tiêu đề AI đổi theo batch không
        // chạm tới đây.
        presentationReader.$snapshot
            .map(\.button)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshButton()
            }
            .store(in: &cancellables)

        // Menu chỉ vẽ khi đang mở, và chỉ **cập nhật** dòng đã có (sáng/xám, badge, chữ) — tập dòng cố định nên
        // không bao giờ phải đóng menu vì "hết mục".
        presentationReader.$snapshot
            .map(\.items)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.viewModel.isMenuOpen else { return }
                self.refreshMenu()
                self.layoutMenu()
            }
            .store(in: &cancellables)

        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.refreshButton()
                if !self.viewModel.isDragging {
                    self.updateLayout(animated: true)
                }
            }
            .store(in: &cancellables)

        // Chỉ báo chưa đọc đổi phía theo mép ⇒ nút phải vẽ lại khi cạnh đổi (chỉ xảy ra lúc nhả tay).
        viewModel.$edgeDirection
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

    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let y = clampedY(viewModel.verticalRatio * bounds.height, height: Layout.size, screenHeight: bounds.height)

        if viewModel.mode == .peeking {
            // Tâm nằm **đúng trên mép** ⇒ một nửa nút ra ngoài, đúng dáng "cất vào mép" của widget TTS.
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

    /// Vẽ lại vị trí theo `mode` hiện tại. `internal` để window manager và file `+Actions` gọi được.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = CGSize(width: Layout.size, height: Layout.size)

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

    /// Đưa hub về trạng thái xuất hiện chuẩn — menu đóng, dạng nép mép. Window manager gọi mỗi lần hub hiện
    /// lại sau khi bị ẩn (cả cửa sổ hoặc chỉ nút).
    func prepareForAppearance() {
        closeMenu(animated: false)
        viewModel.prepareForAppearance()
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

        if viewModel.mode == .peeking {
            viewModel.reveal()
            // `updateLayout` gán ngay vị trí đích cho `widgetContainerView` (animation chỉ chạy ở lớp hiển thị) ⇒
            // `layoutMenu` đặt thẻ đúng cạnh nút đã bung.
            updateLayout(animated: true)
        }
        // Mở menu bật `isMenuOpen` ⇒ huỷ hẹn giờ tự thu.
        openMenu()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        handlePrimaryAction()
    }

    @objc private func handleBackdropTap(_ gesture: UITapGestureRecognizer) {
        // Chạm ngoài thẻ chỉ đóng menu (chạm bị nuốt, kiểu popover); hub vẫn bung và tự thu sau 3 s.
        closeMenu(animated: true)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            // Hạ cờ menu trước tiên: đang kéo mà lớp nền còn sống là nuốt chạm của cả app.
            closeMenu(animated: false)
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
                y: clampedY(rawY, height: Layout.size, screenHeight: container.bounds.height)
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
