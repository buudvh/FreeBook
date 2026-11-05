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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidDisconnect),
            name: UIScene.didDisconnectNotification,
            object: nil
        )
        // Trình phát video toàn màn / khoá màn ⇒ ẩn widget, thoát ra ⇒ hiện lại. `@Published` phát ở willSet nên
        // phải qua `receive(on:)` thì `refreshState` mới đọc được giá trị mới.
        FloatingWidgetSuppression.shared.$isSuppressed
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)
    }

    public func refreshState() {
        let shouldShow = TranslationManager.shared.isInitialized
            && TTSManager.shared.showFloatingWidget
            && !FloatingWidgetSuppression.shared.isSuppressed

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
            move(to: windowScene)
            // Chỉ lúc chuyển từ ẩn sang hiện mới xếp lại chỗ (né widget nổi khác) — `refreshState` gọi lặp vào đây.
            if existingWindow.isHidden {
                containerViewController?.requestPlacementResolve()
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
        FloatingWidgetLayoutCoordinator.shared.unregister(.tts)
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

    /// Chỉ theo scene chứa giao diện chính (`AppMainWindowScene`) — scene của PiP cũng báo `didActivate`.
    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented, let scene = notification.object as? UIWindowScene,
              AppMainWindowScene.isMainInterface(scene) else { return }
        move(to: scene)
        updateWindowVisibility(hidden: false)
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented, let scene = activeWindowScene else { return }
        move(to: scene)
        updateWindowVisibility(hidden: false)
    }

    /// Scene đang giữ widget bị ngắt (vd scene của PiP) ⇒ đưa widget về scene chính.
    @objc private func handleSceneDidDisconnect(_ notification: Notification) {
        guard let window, let scene = notification.object as? UIScene else { return }
        guard window.windowScene == nil || window.windowScene === scene else { return }
        AppLogger.shared.log("🪟 [TTSWidget] Scene giữ widget bị ngắt: \(AppMainWindowScene.describe(scene))")
        if let target = AppMainWindowScene.current(excluding: scene) {
            move(to: target)
        }
        // Lượt sau: lúc này scene đang ngắt có thể còn trong `connectedScenes`, `refreshState` gọi ngay có thể chọn lại nó.
        DispatchQueue.main.async { [weak self] in
            self?.refreshState()
        }
    }

    private func move(to scene: UIWindowScene) {
        guard let window, window.windowScene !== scene else { return }
        AppLogger.shared.log("🪟 [TTSWidget] Chuyển widget sang scene: \(AppMainWindowScene.describe(scene))")
        window.windowScene = scene
        containerViewController?.view.setNeedsLayout()
    }

    private var activeWindowScene: UIWindowScene? {
        AppMainWindowScene.current()
    }
}
