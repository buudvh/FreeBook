import SwiftUI
import UIKit
import Combine

/// View controller của widget AI Agent thu nhỏ: sở hữu cử chỉ `UIPanGestureRecognizer`
/// / `UITapGestureRecognizer` và cập nhật frame trực tiếp trên `UIView` theo hình học của `FloatingWidgetGeometry`.
@MainActor
final class AIFloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    let widgetContainerView = UIView()
    private var hostingController: UIHostingController<AIFloatingWidgetView>?
    private var panStartCenter: CGPoint = .zero
    private var isDragging: Bool = false
    private var cancellables = Set<AnyCancellable>()

    private var verticalRatio: CGFloat = 0.30
    private var edgeDirection: EdgeDirection = .right

    private let storedRatioKey = "aiFloatingWidgetVerticalRatio"
    private let storedEdgeKey = "aiFloatingWidgetEdge"

    private var panGesture: UIPanGestureRecognizer!
    private var tapGesture: UITapGestureRecognizer!

    enum Layout {
        static let minWidth: CGFloat = 80
        static let maxWidth: CGFloat = 260
        static let height: CGFloat = 38
        static let horizontalMargin: CGFloat = 8
        static let verticalMargin: CGFloat = 8
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        loadSavedPosition()

        widgetContainerView.backgroundColor = .clear
        widgetContainerView.clipsToBounds = false
        widgetContainerView.layer.masksToBounds = false
        view.addSubview(widgetContainerView)

        let hosting = UIHostingController(rootView: AIFloatingWidgetView())
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

    private func loadSavedPosition() {
        let storedRatio = UserDefaults.standard.double(forKey: storedRatioKey)
        self.verticalRatio = storedRatio > 0.05 ? CGFloat(storedRatio) : 0.30

        if let rawEdge = UserDefaults.standard.string(forKey: storedEdgeKey),
           let edge = EdgeDirection(rawValue: rawEdge) {
            self.edgeDirection = edge
        } else {
            self.edgeDirection = .right
        }
    }

    private func savePosition() {
        UserDefaults.standard.set(Double(verticalRatio), forKey: storedRatioKey)
        UserDefaults.standard.set(edgeDirection.rawValue, forKey: storedEdgeKey)
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
        AIRuntimeCoordinator.shared.$activeTaskTitle
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self, !self.isDragging else { return }
                self.updateLayout(animated: true)
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if !isDragging {
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
            edge: edgeDirection,
            widgetWidth: size.width,
            screenWidth: bounds.width,
            horizontalMargin: Layout.horizontalMargin
        )
        let y = clampedY(verticalRatio * bounds.height, height: size.height, screenHeight: bounds.height)
        return CGPoint(x: x, y: y)
    }

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
            isDragging = true
            panStartCenter = widgetContainerView.center
        case .changed:
            let translation = gesture.translation(in: container)
            let rawX = panStartCenter.x + translation.x
            let rawY = panStartCenter.y + translation.y
            let clamped = clampedY(rawY, height: currentWidgetSize.height, screenHeight: container.bounds.height)
            widgetContainerView.center = CGPoint(x: rawX, y: clamped)
        case .ended, .cancelled:
            isDragging = false
            let finalPosition = widgetContainerView.center
            edgeDirection = FloatingWidgetGeometry.nearestEdge(
                centerX: finalPosition.x,
                screenWidth: container.bounds.width
            )
            if container.bounds.height > 0 {
                verticalRatio = finalPosition.y / container.bounds.height
            }
            savePosition()
            updateLayout(animated: true)
        default:
            isDragging = false
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard !isDragging else { return }
        AIRuntimeCoordinator.shared.presentFullScreen()
    }
}
