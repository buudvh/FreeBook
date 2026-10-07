import Combine
import SwiftData
import SwiftUI
import UIKit

/// Điều phối `UIWindow` riêng cho **widget thông báo nổi** — nút chuông 36px hiện ở mọi màn **trừ tab Kệ
/// Sách** (Kệ sách / Lịch sử / Tải về / Bộ sưu tập đều đã có nút chuông ở toolbar hoặc nằm trong cùng tab).
///
/// ## Vì sao phải là `UIWindow`, không phải overlay trong `MainTabView`
/// Reader và trình duyệt bypass đều được trình bày bằng `fullScreenCover` (`ShelfView.swift:271,366`), nên
/// một overlay gắn vào `MainTabView` sẽ **bị che** ngay khi người dùng mở truyện — đúng lúc họ cần nút nhất.
/// Ba widget đang có (`TTSFloatingWidgetWindowManager`, `BrowserFloatingWidgetWindowManager`,
/// `AIFloatingWidgetWindowManager`) đều giải quyết cùng vấn đề bằng cửa sổ riêng; đây là cái thứ tư.
///
/// ## Level cửa sổ: thấp hơn cả hai widget kia
/// TTS dùng `alert - 1`, trình duyệt `alert - 2`; nút thông báo đặt **`alert - 3`** để chỗ nào chồng nhau
/// thì hai widget kia nhận chạm trước — nút thông báo là thứ ít khẩn cấp nhất trong ba.
///
/// ## Cửa sổ phải sống trong lúc sheet mở
/// Màn Thông báo được trình bày **từ chính cửa sổ này**, nên khi sheet mở mà ta ẩn cửa sổ thì sheet biến
/// mất theo. Vì vậy `setSheetPresented(true)` chỉ **giấu nút**, không hạ cửa sổ.
@MainActor
final class NotificationFloatingWidgetWindowManager: ObservableObject {
    static let shared = NotificationFloatingWidgetWindowManager()

    /// Khoá `userInfo` của `Notification.Name.appTabDidChange`.
    static let tabIndexUserInfoKey = "index"
    /// Khoá `userInfo` của `Notification.Name.openReaderFromNotification`.
    static let bookIdUserInfoKey = "bookId"
    static let extensionPackageIdUserInfoKey = "extensionPackageId"
    static let chapterIndexUserInfoKey = "chapterIndex"
    static let detailUrlUserInfoKey = "detailUrl"
    static let sourceNameUserInfoKey = "sourceName"

    @Published private(set) var isWidgetActuallyVisible: Bool = false
    /// `ModelContainer` cho sheet màn Thông báo — cửa sổ phụ không có environment của app.
    var modelContainer: ModelContainer?

    /// Tab Kệ Sách là tab 0 của `MainTabView`; mặc định `true` vì app luôn khởi động ở tab đó.
    private(set) var isShelfTabActive = true
    private(set) var isSheetPresented = false

    private let presentationReader = NotificationFloatingWidgetPresentationReader()
    private var window: NotificationFloatingWidgetUIWindow?
    private var containerViewController: NotificationFloatingWidgetContainerViewController?
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

        NotificationCenter.default
            .publisher(for: .appTabDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self else { return }
                guard let index = notification.userInfo?[Self.tabIndexUserInfoKey] as? Int else { return }
                self.isShelfTabActive = (index == 0)
                self.refreshState()
            }
            .store(in: &cancellables)

        presentationReader.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self else { return }
                // Có việc mới mà nút đang không hiện ⇒ lần hiện tới bung ra, để người dùng thấy con số.
                if snapshot.shouldShowWidget, !self.isWidgetActuallyVisible {
                    self.shouldRevealOnNextShow = true
                }
                self.refreshState()
            }
            .store(in: &cancellables)
    }

    /// Cửa duy nhất để đồng bộ hiển thị. Gọi ở lúc khởi động, khi đổi tab, khi có việc mới, và khi sheet
    /// đóng/mở — không nơi nào tự bật/tắt cửa sổ.
    func refreshState() {
        let shouldShowButton = TranslationManager.shared.isInitialized
            && !isShelfTabActive
            && !isSheetPresented
            && presentationReader.snapshot.shouldShowWidget

        if shouldShowButton {
            showWidget()
        } else if isSheetPresented {
            // Cửa sổ phải sống để giữ sheet đang mở; chỉ giấu nút.
            updateWindowVisibility(hidden: false)
            containerViewController?.widgetContainerView.isHidden = true
        } else {
            hideWidget()
        }
    }

    func setSheetPresented(_ presented: Bool) {
        guard isSheetPresented != presented else { return }
        isSheetPresented = presented
        if presented {
            containerViewController?.widgetContainerView.isHidden = true
        }
        refreshState()
    }

    private func showWidget() {
        guard let windowScene = activeWindowScene else { return }

        if let existingWindow = window {
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
            updateWindowVisibility(hidden: false)
            containerViewController?.widgetContainerView.isHidden = false
            isPresented = true
            revealIfRequested(animated: false)
            containerViewController?.updateLayout(animated: false)
            return
        }

        let containerVC = NotificationFloatingWidgetContainerViewController()
        let win = NotificationFloatingWidgetUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 3)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        // Không bao giờ `makeKeyAndVisible()`: đây là lớp phủ, không phải cửa sổ chính.
        updateWindowVisibility(hidden: false)
        revealIfRequested(animated: false)
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

    private func revealIfRequested(animated: Bool) {
        guard shouldRevealOnNextShow, let containerViewController else { return }
        shouldRevealOnNextShow = false
        containerViewController.reveal(animated: animated)
    }

    @objc private func handleSceneDidActivate(_ notification: Notification) {
        guard isPresented || isSheetPresented, let scene = notification.object as? UIWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        updateWindowVisibility(hidden: false)
    }

    @objc private func handleDidBecomeActive() {
        guard isPresented || isSheetPresented, let scene = activeWindowScene else { return }
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

extension Notification.Name {
    /// `MainTabView` vừa đổi tab. `selectedTab` là `@State` cục bộ nên widget nổi không đọc trực tiếp được.
    static let appTabDidChange = Notification.Name("appTabDidChange")

    /// Mở Reader cho một truyện cụ thể, phát từ widget nổi; `ShelfView` là nơi nhận vì chỉ nó giữ
    /// `fullScreenCover` của Reader. `userInfo` mang đủ trường của `ShelfReaderRoute`.
    static let openReaderFromNotification = Notification.Name("openReaderFromNotification")
}
