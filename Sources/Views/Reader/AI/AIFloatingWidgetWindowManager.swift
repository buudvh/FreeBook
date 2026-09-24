import SwiftUI
import UIKit
import Combine

/// Điều phối `UIWindow` riêng cho widget AI Agent thu nhỏ nổi trên toàn bộ màn hình (Reader, Shelf, Discovery...).
/// Cửa sổ này luôn là non-key window (không bao giờ gọi makeKeyAndVisible), nền trong suốt,
/// và passthrough touch chuẩn xác để không chặn thao tác ở màn hình bên dưới.
///
/// Level đặt thấp hơn Browser widget và TTS widget (`alert - 3`) để các widget cùng tồn tại mà không tranh hit-testing.
@MainActor
public final class AIFloatingWidgetWindowManager: ObservableObject {
    public static let shared = AIFloatingWidgetWindowManager()

    @Published public private(set) var isWidgetActuallyVisible: Bool = false

    private var window: AIFloatingWidgetUIWindow?
    private var containerViewController: AIFloatingWidgetContainerViewController?
    private var isPresented = false
    private var cancellables = Set<AnyCancellable>()

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

        Publishers.CombineLatest(
            AIRuntimeCoordinator.shared.$isRunning,
            AIRuntimeCoordinator.shared.$isFullScreenPresented
        )
        .receive(on: RunLoop.main)
        .sink { [weak self] isRunning, isPresented in
            self?.refreshState(isRunning: isRunning, isFullScreenPresented: isPresented)
        }
        .store(in: &cancellables)
    }

    /// Làm mới trạng thái hiển thị của widget AI.
    public func refreshState(isRunning: Bool? = nil, isFullScreenPresented: Bool? = nil) {
        let running = isRunning ?? AIRuntimeCoordinator.shared.isRunning
        let fullScreen = isFullScreenPresented ?? AIRuntimeCoordinator.shared.isFullScreenPresented

        let shouldShow = running && !fullScreen

        if shouldShow {
            showWidget()
        } else {
            hideWidget()
        }
    }

    private func showWidget() {
        guard let windowScene = activeWindowScene else { return }

        if let existingWindow = window {
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
            updateWindowVisibility(hidden: false)
            isPresented = true
            containerViewController?.updateLayout(animated: false)
            return
        }

        let containerVC = AIFloatingWidgetContainerViewController()
        let win = AIFloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 3)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        updateWindowVisibility(hidden: false)
    }

    public func hideWidget() {
        updateWindowVisibility(hidden: true)
        isPresented = false
    }

    private func updateWindowVisibility(hidden: Bool) {
        window?.isHidden = hidden
        let actuallyVisible = !(window?.isHidden ?? true)
        if isWidgetActuallyVisible != actuallyVisible {
            isWidgetActuallyVisible = actuallyVisible
        }
    }

    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented, let scene = notification.object as? UIWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        updateWindowVisibility(hidden: false)
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented, let scene = activeWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        updateWindowVisibility(hidden: false)
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}
