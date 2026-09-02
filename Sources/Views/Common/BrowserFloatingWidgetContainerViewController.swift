import SwiftUI
import UIKit
import Combine

/// View controller của widget trình duyệt thu nhỏ: sở hữu cử chỉ `UIPanGestureRecognizer`
/// / `UITapGestureRecognizer` và cập nhật frame trực tiếp trên `UIView`, đúng kiến trúc
/// đang dùng cho TTS widget (`FloatingWidgetContainerViewController`) thay vì kéo/thả
/// thuần SwiftUI — nhờ vậy ngón tay không bị trễ theo vòng cập nhật state của SwiftUI.
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
        static let minWidth: CGFloat = 74
        static let maxWidth: CGFloat = 240
        /// Bằng **2/3** chiều cao widget nghe truyện (`FloatingWidgetContainerViewController.Layout
        /// .height` = 56): cùng một họ hình khối nhưng nhỏ hơn, vì widget này chỉ có một dòng "N tab".
        static let height: CGFloat = 38
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 8
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        tabCount = presentationReader.snapshot.tabCount
        let hosting = UIHostingController(rootView: VisibleBrowserReopenButton(tabCount: tabCount))
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
                self.hostingController?.rootView = VisibleBrowserReopenButton(tabCount: snapshot.tabCount)
                if !self.viewModel.isDragging {
                    self.updateLayout(animated: true)
                }
            }
            .store(in: &cancellables)
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

    private var currentWidgetSize: CGSize {
        let fitting = hostingController?.sizeThatFits(
            in: CGSize(width: Layout.maxWidth, height: Layout.height)
        ) ?? .zero
        let width = min(Layout.maxWidth, max(Layout.minWidth, ceil(fitting.width)))
        let height = max(Layout.height, ceil(fitting.height))
        return CGSize(width: width, height: height)
    }

    private func restingCenter(in bounds: CGRect) -> CGPoint {
        guard bounds.width > 0, bounds.height > 0 else { return .zero }
        let size = currentWidgetSize
        let x = FloatingWidgetGeometry.restingCenterX(
            edge: viewModel.edgeDirection,
            widgetWidth: size.width,
            screenWidth: bounds.width,
            horizontalMargin: Layout.horizontalMargin
        )
        let y = clampedY(viewModel.verticalRatio * bounds.height, height: size.height, screenHeight: bounds.height)
        return CGPoint(x: x, y: y)
    }

    /// Kẹp theo safe area để widget không bao giờ ra ngoài vùng hiển thị hợp lệ.
    private func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: height,
            screenHeight: screenHeight,
            topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
            bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
        )
    }

    func updateLayout(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let targetSize = currentWidgetSize
        let targetCenter = restingCenter(in: view.bounds)

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

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = self.view else { return }
        switch gesture.state {
        case .began:
            viewModel.handleDragStart()
            panStartCenter = widgetContainerView.center
        case .changed:
            let translation = gesture.translation(in: container)
            let rawX = panStartCenter.x + translation.x
            let rawY = panStartCenter.y + translation.y
            let size = widgetContainerView.bounds.size
            let clamped = clampedY(rawY, height: size.height, screenHeight: container.bounds.height)
            widgetContainerView.center = CGPoint(x: rawX, y: clamped)
        case .ended, .cancelled:
            let bounds = container.bounds
            viewModel.handleDragEnd(
                finalPosition: widgetContainerView.center,
                widgetHeight: widgetContainerView.bounds.height,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                topMargin: view.safeAreaInsets.top + Layout.verticalMargin,
                bottomMargin: view.safeAreaInsets.bottom + Layout.verticalMargin
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
