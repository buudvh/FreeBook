import SwiftUI
import UIKit
import Combine

/// Điều phối UIWindow riêng cho widget TTS nổi trên toàn bộ màn hình (Reader, Bypass WebView, Visible Browser, Sheets...).
/// Cửa sổ này luôn là non-key window (không bao giờ gọi makeKeyAndVisible), nền trong suốt,
/// và passthrough touch chuẩn xác để không chặn thao tác ở màn hình bên dưới.
@MainActor
public final class TTSFloatingWidgetWindowManager {
    public static let shared = TTSFloatingWidgetWindowManager()

    private var window: FloatingWidgetUIWindow?
    private var containerViewController: FloatingWidgetContainerViewController?
    private var isPresented = false

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidActivate),
            name: UIScene.didActivateNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    public func refreshState() {
        let shouldShow = TranslationManager.shared.isInitialized
            && TTSManager.shared.showFloatingWidget
            && !TTSManager.shared.showingSettingsSheet

        if shouldShow {
            showWidget()
        } else {
            hideWidget()
        }
    }

    public func showWidget() {
        guard let windowScene = activeWindowScene else {
            return
        }

        if let existingWindow = window {
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
            if existingWindow.isHidden {
                existingWindow.isHidden = false
            }
            isPresented = true
            containerViewController?.updateLayoutForCurrentMode(animated: false)
            return
        }

        let containerVC = FloatingWidgetContainerViewController()
        let win = FloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        // Chỉ bật hiển thị cửa sổ, TUYỆT ĐỐI không gọi makeKeyAndVisible() để không cướp keyWindow
        win.isHidden = false
    }

    public func hideWidget() {
        guard let window else { return }
        window.isHidden = true
        isPresented = false
    }

    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented, let scene = notification.object as? UIWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented, let scene = activeWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}

/// Overlay UIWindow có nền trong suốt, là ranh giới hit-testing duy nhất có thẩm quyền.
@MainActor
final class FloatingWidgetUIWindow: UIWindow {
    weak var containerViewController: FloatingWidgetContainerViewController?

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Khi container đang hiển thị confirmationDialog hoặc alert, cho phép touch đầy đủ để tương tác dialog
        if containerViewController?.presentedViewController != nil {
            return super.hitTest(point, with: event)
        }

        guard let widgetView = containerViewController?.widgetContainerView,
              !widgetView.isHidden,
              widgetView.alpha > 0.01,
              widgetView.isUserInteractionEnabled else {
            return nil
        }

        let localPoint = widgetView.convert(point, from: self)
        guard widgetView.point(inside: localPoint, with: event) else {
            return nil
        }

        return super.hitTest(point, with: event)
    }
}

/// View controller quản lý widget container, cử chỉ UIPan / UITap và animation chuyển đổi vị trí/kích thước.
@MainActor
final class FloatingWidgetContainerViewController: UIViewController, UIGestureRecognizerDelegate {
    private let viewModel = FloatingWidgetViewModel()
    let widgetContainerView = UIView()
    private var hostingController: UIHostingController<TTSWidgetContentView>?
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

        let contentView = TTSWidgetContentView(viewModel: viewModel)
        let hosting = UIHostingController(rootView: contentView)
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
            let halfWidth = size.width / 2
            let x = viewModel.edgeDirection == .left
                ? (Layout.horizontalMargin + halfWidth)
                : (screenWidth - Layout.horizontalMargin - halfWidth)
            return CGPoint(x: x, y: y)
        }
    }

    private func clampedY(_ value: CGFloat, height: CGFloat, screenHeight: CGFloat) -> CGFloat {
        let minY = Layout.verticalMargin + height / 2
        let maxY = max(minY, screenHeight - Layout.verticalMargin - height / 2)
        return min(max(value, minY), maxY)
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
