import SwiftUI
import UIKit
import Combine
import SwiftData

/// View controller quản lý widget container, cử chỉ UIPan / UITap và animation chuyển đổi vị trí/kích thước.
@MainActor
final class FloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let viewModel = FloatingWidgetViewModel()
    private let rotationState = CoverRotationState()
    private var lastDistinctBookId: String = ""
    let widgetContainerView = UIView()
    private var hostingController: UIHostingController<AnyView>?
    private var panStartCenter: CGPoint = .zero
    private var cancellables = Set<AnyCancellable>()

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    enum Layout {
        static let width: CGFloat = 212
        static let height: CGFloat = 56
        static let timerExtraHeight: CGFloat = 24
        static let peekSize: CGFloat = 52
        static let horizontalMargin: CGFloat = 0
        static let verticalMargin: CGFloat = 92
        static let edgeSnapDistance: CGFloat = 40
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        let contentView = TTSWidgetContentView(viewModel: viewModel, rotationState: rotationState)
        let hostingView: AnyView
        if let container = TTSFloatingWidgetWindowManager.shared.modelContainer {
            hostingView = AnyView(contentView.modelContainer(container))
        } else {
            hostingView = AnyView(contentView)
        }
        let hosting = UIHostingController(rootView: hostingView)
        hosting.view.backgroundColor = .clear
        hosting.view.clipsToBounds = false
        hosting.view.layer.masksToBounds = false

        addChild(hosting)
        widgetContainerView.addSubview(hosting.view)
        hosting.didMove(toParent: self)
        self.hostingController = hosting

        setupGestures()
        bindViewModel()
        updateLayoutForCurrentMode(animated: false)
    }

    private func setupGestures() {
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        panGesture.cancelsTouchesInView = true
        widgetContainerView.addGestureRecognizer(panGesture)

        tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tapGesture.delegate = self
        tapGesture.cancelsTouchesInView = true
        tapGesture.isEnabled = (viewModel.mode == .peeking)
        widgetContainerView.addGestureRecognizer(tapGesture)
    }

    private func bindViewModel() {
        viewModel.$mode
            .receive(on: RunLoop.main)
            .sink { [weak self] newMode in
                guard let self else { return }
                self.tapGesture.isEnabled = (newMode == .peeking)
                if !self.viewModel.isDragging {
                    self.updateLayoutForCurrentMode(animated: true)
                }
            }
            .store(in: &cancellables)

        TTSManager.shared.$timerMode
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, !self.viewModel.isDragging else { return }
                self.updateLayoutForCurrentMode(animated: true)
            }
            .store(in: &cancellables)

        TTSManager.shared.$isPlaying
            .receive(on: RunLoop.main)
            .sink { [weak self] isPlaying in
                self?.rotationState.syncPlaybackState(isPlaying: isPlaying, at: Date())
            }
            .store(in: &cancellables)

        TTSManager.shared.$playingBookId
            .receive(on: RunLoop.main)
            .sink { [weak self] newBookId in
                guard let self else { return }
                guard !newBookId.isEmpty else { return }
                if !self.lastDistinctBookId.isEmpty {
                    if self.lastDistinctBookId != newBookId {
                        self.lastDistinctBookId = newBookId
                        self.rotationState.resetAngle(isPlaying: TTSManager.shared.isPlaying, at: Date())
                    }
                } else {
                    self.lastDistinctBookId = newBookId
                }
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !viewModel.isDragging {
            updateLayoutForCurrentMode(animated: false)
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { [weak self] _ in
            self?.updateLayoutForCurrentMode(animated: false)
        }
    }

    private var currentWidgetSize: CGSize {
        if viewModel.mode == .peeking {
            return CGSize(width: Layout.peekSize, height: Layout.peekSize)
        } else {
            let isTimerActive = TTSManager.shared.timerMode != .off
            let height = isTimerActive ? (Layout.height + Layout.timerExtraHeight) : Layout.height
            return CGSize(width: Layout.width, height: height)
        }
    }

    private func restingCenter(for mode: WidgetMode, in bounds: CGRect) -> CGPoint {
        let screenWidth = bounds.width
        let screenHeight = bounds.height
        guard screenWidth > 0, screenHeight > 0 else { return .zero }

        let size = currentWidgetSize
        let y = clampedY(viewModel.verticalRatio * screenHeight, height: size.height, screenHeight: screenHeight)

        if mode == .peeking {
            let x = viewModel.edgeDirection == .left ? 0 : screenWidth
            return CGPoint(x: x, y: y)
        } else {
            let x = FloatingWidgetGeometry.restingCenterX(
                edge: viewModel.edgeDirection,
                widgetWidth: size.width,
                screenWidth: screenWidth,
                horizontalMargin: Layout.horizontalMargin
            )
            return CGPoint(x: x, y: y)
        }
    }

    private func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        FloatingWidgetGeometry.clampedCenterY(
            value,
            widgetHeight: height,
            screenHeight: screenHeight,
            topMargin: Layout.verticalMargin,
            bottomMargin: Layout.verticalMargin
        )
    }

    public func updateLayoutForCurrentMode(animated: Bool) {
        guard view.bounds.width > 0, view.bounds.height > 0 else { return }
        let targetSize = currentWidgetSize
        let targetCenter = restingCenter(for: viewModel.mode, in: view.bounds)

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
            if viewModel.mode == .peeking {
                viewModel.reveal()
                updateLayoutForCurrentMode(animated: true)
            }
        case .changed:
            let translation = gesture.translation(in: container)
            let rawX = panStartCenter.x + translation.x
            let rawY = panStartCenter.y + translation.y
            let bounds = container.bounds
            let size = widgetContainerView.bounds.size
            let clamped = clampedY(rawY, height: size.height, screenHeight: bounds.height)
            widgetContainerView.center = CGPoint(x: rawX, y: clamped)
        case .ended, .cancelled:
            let bounds = container.bounds
            let finalPosition = widgetContainerView.center
            viewModel.handleDragEnd(
                finalPosition: finalPosition,
                widgetWidth: Layout.width,
                widgetHeight: Layout.height,
                screenWidth: bounds.width,
                screenHeight: bounds.height,
                edgeSnapDistance: Layout.edgeSnapDistance
            )
            updateLayoutForCurrentMode(animated: true)
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard viewModel.mode == .peeking else { return }
        viewModel.reveal()
        updateLayoutForCurrentMode(animated: true)
    }

    // MARK: - UIGestureRecognizerDelegate
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return false
    }
}
