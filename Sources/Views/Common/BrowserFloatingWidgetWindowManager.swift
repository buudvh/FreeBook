import SwiftUI
import UIKit
import Combine

/// Điều phối `UIWindow` riêng cho widget trình duyệt thu nhỏ, cùng kiến trúc với
/// `TTSFloatingWidgetWindowManager`. Window luôn non-key (không bao giờ
/// `makeKeyAndVisible()`), nền trong suốt, passthrough touch ngoài viên pill.
///
/// Level đặt thấp hơn TTS widget một bậc (`alert - 2`) để hai widget cùng tồn tại mà
/// không tranh hit-testing: chỗ nào chồng nhau thì TTS widget nhận trước.
@MainActor
final class BrowserFloatingWidgetWindowManager: ObservableObject {
    static let shared = BrowserFloatingWidgetWindowManager()

    @Published private(set) var isWidgetActuallyVisible: Bool = false

    private var window: BrowserFloatingWidgetUIWindow?
    private var containerViewController: BrowserFloatingWidgetContainerViewController?
    private var isPresented = false
    private var cancellable: AnyCancellable?

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
        cancellable = NotificationCenter.default
            .publisher(for: VisibleBrowserTabManager.stateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
    }

    /// Chỉ hiện widget khi trình duyệt đang thu nhỏ và còn tab sống.
    func refreshState() {
        let manager = VisibleBrowserTabManager.shared
        let shouldShow = TranslationManager.shared.isInitialized
            && manager.isHidden
            && !manager.tabs.isEmpty

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

        let containerVC = BrowserFloatingWidgetContainerViewController()
        let win = BrowserFloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 2)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        updateWindowVisibility(hidden: false)
    }

    private func hideWidget() {
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
