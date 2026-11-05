import Combine
import UIKit

/// Điều phối `UIWindow` riêng cho widget trình duyệt thu nhỏ — dựng lại ở 1.3.533 sau khi trình duyệt rời
/// nút hub nổi (gộp ở 1.3.524). Window luôn non-key (không bao giờ `makeKeyAndVisible()`), nền trong suốt,
/// passthrough touch ngoài vòng tròn của nút.
///
/// ## Khi nào hiện
/// Cổng từ điển đã mở **và** trình duyệt đang thu nhỏ **và** còn tab (`VisibleBrowserPresentationReader`
/// `.showReopenButton`) **và** trình phát video không đang toàn màn (`FloatingWidgetSuppression`).
///
/// ## Level cửa sổ: `alert - 3`
/// TTS `alert - 1`, hub `alert - 2`, widget này `alert - 3`: chỗ chồng nhau thì TTS rồi hub nhận chạm trước.
///
/// ## Một reader duy nhất
/// Manager sở hữu đúng **một** `VisibleBrowserPresentationReader` và tiêm vào container — không dựng thêm bộ
/// subscription thứ hai cho cùng dữ liệu.
@MainActor
final class BrowserFloatingWidgetWindowManager {
    static let shared = BrowserFloatingWidgetWindowManager()

    let presentationReader = VisibleBrowserPresentationReader()

    private var window: BrowserFloatingWidgetUIWindow?
    private var containerViewController: BrowserFloatingWidgetContainerViewController?
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSceneDidDisconnect),
            name: UIScene.didDisconnectNotification,
            object: nil
        )

        // `@Published` phát ở willSet ⇒ hai nhánh đều qua `receive(on:)` để `refreshState` đọc giá trị mới.
        presentationReader.$snapshot
            .map(\.showReopenButton)
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)

        FloatingWidgetSuppression.shared.$isSuppressed
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)
    }

    /// Cửa duy nhất để đồng bộ hiển thị. Gọi ở lúc khởi động, khi cổng từ điển mở (`AppLaunchRootView`), khi
    /// trạng thái trình duyệt đổi và khi cờ ẩn widget đổi. Rẻ khi gọi lặp.
    func refreshState() {
        let shouldShow = TranslationManager.shared.isInitialized
            && presentationReader.snapshot.showReopenButton
            && !FloatingWidgetSuppression.shared.isSuppressed

        if shouldShow {
            showWidget()
        } else {
            hideWidget()
        }
    }

    private func showWidget() {
        guard let windowScene = activeWindowScene else { return }

        if let existingWindow = window, let containerViewController {
            move(to: windowScene)
            // Đang ẩn mà sắp hiện lại ⇒ luôn về dạng nép mép, mờ khi nghỉ, và xếp lại chỗ để né widget nổi khác
            // (`prepareForAppearance` bật cờ xếp lại).
            if existingWindow.isHidden {
                containerViewController.prepareForAppearance()
            }
            existingWindow.isHidden = false
            isPresented = true
            return
        }

        let containerVC = BrowserFloatingWidgetContainerViewController(presentationReader: presentationReader)
        let win = BrowserFloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 3)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        // Không bao giờ `makeKeyAndVisible()`: đây là lớp phủ, không phải cửa sổ chính.
        win.isHidden = false
    }

    private func hideWidget() {
        window?.isHidden = true
        isPresented = false
        FloatingWidgetLayoutCoordinator.shared.unregister(.browser)
    }

    /// Chỉ theo scene chứa giao diện chính (`AppMainWindowScene`) — scene của PiP cũng báo `didActivate`.
    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented, let scene = notification.object as? UIWindowScene,
              AppMainWindowScene.isMainInterface(scene) else { return }
        move(to: scene)
        window?.isHidden = false
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented, let scene = activeWindowScene else { return }
        move(to: scene)
        window?.isHidden = false
    }

    /// Scene đang giữ widget bị ngắt (vd scene của PiP) ⇒ đưa widget về scene chính.
    @objc private func handleSceneDidDisconnect(_ notification: Notification) {
        guard let window, let scene = notification.object as? UIScene else { return }
        guard window.windowScene == nil || window.windowScene === scene else { return }
        AppLogger.shared.log("🪟 [BrowserWidget] Scene giữ widget bị ngắt: \(AppMainWindowScene.describe(scene))")
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
        AppLogger.shared.log("🪟 [BrowserWidget] Chuyển widget sang scene: \(AppMainWindowScene.describe(scene))")
        window.windowScene = scene
        containerViewController?.view.setNeedsLayout()
    }

    private var activeWindowScene: UIWindowScene? {
        AppMainWindowScene.current()
    }
}
