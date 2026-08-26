import SwiftUI
import UIKit
import Combine
import SwiftData

/// Điều phối UIWindow riêng cho widget TTS nổi trên toàn bộ màn hình (Reader, Bypass WebView, Visible Browser, Sheets...).
/// Cửa sổ này luôn là non-key window (không bao giờ gọi makeKeyAndVisible), nền trong suốt,
/// và passthrough touch chuẩn xác để không chặn thao tác ở màn hình bên dưới.
@MainActor
public final class TTSFloatingWidgetWindowManager: ObservableObject {
    public static let shared = TTSFloatingWidgetWindowManager()

    @Published public private(set) var isWidgetActuallyVisible: Bool = false
    public var modelContainer: ModelContainer?
    private var window: FloatingWidgetUIWindow?
    private var containerViewController: FloatingWidgetContainerViewController?
    private var isPresented = false
    private var shouldRevealOnNextShow = false

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
            updateWindowVisibility(hidden: false)
            isPresented = true
            revealIfRequested(animated: false)
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

        // Chỉ bật hiển thị cửa sổ qua hàm tập trung, TUYỆT ĐỐI không gọi makeKeyAndVisible()
        updateWindowVisibility(hidden: false)
        revealIfRequested(animated: false)
    }

    func requestRevealOnNextShow() {
        shouldRevealOnNextShow = true
        revealIfRequested(animated: isWidgetActuallyVisible)
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

    private func revealIfRequested(animated: Bool) {
        guard shouldRevealOnNextShow, let containerViewController else { return }
        shouldRevealOnNextShow = false
        containerViewController.reveal(animated: animated)
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
