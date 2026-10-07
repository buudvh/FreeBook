import Combine
import SwiftUI
import UIKit

/// View controller của widget trình duyệt thu nhỏ: sở hữu `UIPanGestureRecognizer` /
/// `UITapGestureRecognizer` và cập nhật frame trực tiếp trên `UIView`, đúng kiến trúc đang dùng cho TTS
/// widget (`FloatingWidgetContainerViewController`) thay vì kéo/thả thuần SwiftUI — nhờ vậy ngón tay không
/// bị trễ theo vòng cập nhật state của SwiftUI.
///
/// ## Một cỡ, hai vị trí (1.3.476)
/// Bản cũ là **pill** co giãn theo nội dung (`sizeThatFits`, rộng 74–240, cao 38) và **không** có trạng thái
/// thu gọn. Nay theo đúng khuôn widget thông báo: nút tròn **36px**, `.peeking` là nút **ngậm vào mép** (tâm
/// nằm đúng trên mép nên một nửa ra ngoài), `.revealed` là nút nằm trong màn với lề ngang nhỏ. Nhờ một cỡ
/// duy nhất, animation thu/bung chỉ là **dịch chuyển**, không phải đổi kích thước view.
///
/// Level cửa sổ vẫn do `BrowserFloatingWidgetWindowManager` quyết định (`alert - 2`) — file này không đụng.
@MainActor
final class BrowserFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let viewModel = VisibleBrowserReopenViewModel()
    private let presentationReader = VisibleBrowserPresentationReader()
    let widgetContainerView = UIView()
    private var hostingController: UIHostingController<VisibleBrowserReopenButton>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()
    private var tabCount: Int = 0

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    enum Layout {
        static let size: CGFloat = VisibleBrowserReopenButton.size
        /// Lề ngang khi nút ở dạng bung — nhỏ, vì nút vốn đã nhỏ.
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 12
        /// Thả trong khoảng này tính là "dán mép" ⇒ thu gọn.
        static let edgeSnapDistance: CGFloat = 26
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
            mode: viewModel.mode,
            edge: viewModel.edgeDirection
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
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                guard snapshot.tabCount != self.tabCount else { return }
                self.tabCount = snapshot.tabCount
                self.refreshContent()
                if !self.viewModel.isDragging {
                    self.updateLayout(animated: true)
                }
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

    /// Vẽ lại vị trí theo `mode` hiện tại.
    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let targetCenter = restingCenter(in: view.bounds)
        let targetSize = CGSize(width: Layout.size, height: Layout.size)

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

    /// Bung nút ra khỏi mép.
    func reveal(animated: Bool) {
        viewModel.reveal()
        updateLayout(animated: animated)
    }

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
            updateLayout(animated: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
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
