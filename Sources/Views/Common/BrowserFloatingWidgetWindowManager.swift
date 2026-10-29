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
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
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

    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented, let scene = notification.object as? UIWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        window?.isHidden = false
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented, let scene = activeWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        window?.isHidden = false
    }

    private var activeWindowScene: UIWindowScene? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        return scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
            ?? scenes.first
    }
}
