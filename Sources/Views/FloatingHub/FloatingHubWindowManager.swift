import Combine
import SwiftData
import UIKit

/// Điều phối `UIWindow` riêng cho **nút hub nổi** (1.3.524) — một nút gộp các lối tắt: Trợ lý AI, Thông báo
/// và (từ 1.3.533) Video phát nền. Trình duyệt thu nhỏ đã quay về cửa sổ riêng (`BrowserFloatingWidgetWindowManager`).
///
/// ## Luôn hiện (1.3.533)
/// Hub hiện cả khi không mục nào hoạt động — mục không dùng được thì xám trong menu. Chỉ ẩn ở ba trường hợp:
/// cổng từ điển chưa mở, sheet của chính hub đang mở (chỉ giấu nút, xem dưới), và
/// `FloatingWidgetSuppression.isSuppressed` (trình phát video toàn màn / khoá màn).
///
/// ## Vì sao phải là `UIWindow`, không phải overlay trong `MainTabView`
/// Reader và trình duyệt bypass đều được trình bày bằng `fullScreenCover`, nên một overlay gắn vào
/// `MainTabView` sẽ **bị che** ngay khi người dùng mở truyện — đúng lúc họ cần nút nhất.
///
/// ## Level cửa sổ: `alert - 2`
/// TTS (`alert - 1`) nằm trên và nhận chạm trước ở vùng chồng nhau; widget trình duyệt (`alert - 3`) nằm dưới.
///
/// ## Cửa sổ phải sống trong lúc sheet mở
/// Màn Thông báo được trình bày **từ chính cửa sổ này**, nên khi sheet mở mà ta ẩn cửa sổ thì sheet biến
/// mất theo. Vì vậy `setSheetPresented(true)` chỉ **giấu nút**, không hạ cửa sổ.
///
/// ## Luôn xuất hiện ở dạng nép mép
/// Mỗi lần hub hiện lại sau khi bị ẩn (cả cửa sổ hoặc chỉ nút), container được `prepareForAppearance()` —
/// menu đóng, nút về `.peeking`. Không còn `shouldRevealOnNextShow` của widget thông báo cũ.
@MainActor
final class FloatingHubWindowManager {
    static let shared = FloatingHubWindowManager()

    /// Khoá `userInfo` của `Notification.Name.appTabDidChange`.
    static let tabIndexUserInfoKey = "index"
    /// Khoá `userInfo` của `Notification.Name.openReaderFromNotification`.
    static let bookIdUserInfoKey = "bookId"
    static let extensionPackageIdUserInfoKey = "extensionPackageId"
    static let chapterIndexUserInfoKey = "chapterIndex"
    static let detailUrlUserInfoKey = "detailUrl"
    static let sourceNameUserInfoKey = "sourceName"

    /// `ModelContainer` cho sheet màn Thông báo — cửa sổ phụ không có environment của app.
    var modelContainer: ModelContainer?
    /// Reader **duy nhất** của hub; container nhận nó qua `init`.
    let presentationReader = FloatingHubPresentationReader()
    private(set) var isSheetPresented = false

    private var window: FloatingHubUIWindow?
    private var containerViewController: FloatingHubContainerViewController?
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

        // Snapshot không còn quyết định hiện/ẩn (hub luôn hiện), nên chỉ nghe cờ ẩn widget của trình phát video.
        // `@Published` phát ở willSet ⇒ phải qua `receive(on:)` thì `refreshState` mới đọc được giá trị mới.
        FloatingWidgetSuppression.shared.$isSuppressed
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.refreshState()
            }
            .store(in: &cancellables)
    }

    /// Cửa duy nhất để đồng bộ hiển thị. Gọi ở lúc khởi động, khi cổng từ điển mở, khi cờ ẩn widget đổi, và
    /// khi sheet đóng/mở — không nơi nào tự bật/tắt cửa sổ. Rẻ khi gọi lặp: hub đang hiện thì không làm gì thêm.
    ///
    /// Thứ tự nhánh là bắt buộc: đang ẩn vì trình phát video mà sheet Thông báo còn mở thì rơi vào nhánh
    /// `isSheetPresented` (giữ cửa sổ, chỉ giấu nút) — `hideWidget()` lúc đó sẽ cuốn mất sheet.
    func refreshState() {
        let shouldShowButton = TranslationManager.shared.isInitialized
            && !isSheetPresented
            && !FloatingWidgetSuppression.shared.isSuppressed

        if shouldShowButton {
            showWidget()
        } else if isSheetPresented {
            // Cửa sổ phải sống để giữ sheet đang mở; chỉ giấu nút (và chắc chắn menu đã đóng).
            window?.isHidden = false
            containerViewController?.closeMenu(animated: false)
            containerViewController?.widgetContainerView.isHidden = true
        } else {
            hideWidget()
        }
    }

    func setSheetPresented(_ presented: Bool) {
        guard isSheetPresented != presented else { return }
        isSheetPresented = presented
        if presented {
            containerViewController?.closeMenu(animated: false)
            containerViewController?.widgetContainerView.isHidden = true
        }
        refreshState()
    }

    private func showWidget() {
        guard let windowScene = activeWindowScene else { return }

        if let existingWindow = window, let containerViewController {
            if existingWindow.windowScene !== windowScene {
                existingWindow.windowScene = windowScene
            }
            // Đang ẩn (cả cửa sổ hoặc chỉ nút) mà sắp hiện lại ⇒ luôn về dạng nép mép, menu đóng.
            if existingWindow.isHidden || containerViewController.widgetContainerView.isHidden {
                containerViewController.prepareForAppearance()
            }
            existingWindow.isHidden = false
            containerViewController.widgetContainerView.isHidden = false
            isPresented = true
            return
        }

        let containerVC = FloatingHubContainerViewController(presentationReader: presentationReader)
        let win = FloatingHubUIWindow(windowScene: windowScene)
        win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 2)
        win.backgroundColor = .clear
        win.containerViewController = containerVC
        win.rootViewController = containerVC

        self.containerViewController = containerVC
        self.window = win
        self.isPresented = true

        // Không bao giờ `makeKeyAndVisible()`: đây là lớp phủ, không phải cửa sổ chính.
        win.isHidden = false
    }

    /// Đóng menu **trước** khi ẩn cửa sổ: cờ menu kẹt ở `true` là lớp nền nuốt chạm của cả app khi hub hiện lại.
    private func hideWidget() {
        containerViewController?.closeMenu(animated: false)
        window?.isHidden = true
        isPresented = false
    }

    @objc private func handleSceneDidActivate(_ notification: Notification) {
        // Đổi/quay lại scene: menu luôn đóng — không để lớp nền nuốt chạm sống qua lượt chuyển cảnh.
        containerViewController?.closeMenu(animated: false)
        guard isPresented || isSheetPresented, let scene = notification.object as? UIWindowScene else { return }
        if window?.windowScene !== scene {
            window?.windowScene = scene
            containerViewController?.view.setNeedsLayout()
        }
        window?.isHidden = false
    }

    @objc private func handleDidBecomeActive() {
        containerViewController?.closeMenu(animated: false)
        guard isPresented || isSheetPresented, let scene = activeWindowScene else { return }
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

extension Notification.Name {
    /// `MainTabView` vừa đổi tab. `selectedTab` là `@State` cục bộ nên nút hub nổi không đọc trực tiếp được.
    static let appTabDidChange = Notification.Name("appTabDidChange")

    /// Mở Reader cho một truyện cụ thể, phát từ màn Thông báo mở qua nút hub nổi; `ShelfView` là nơi nhận vì
    /// chỉ nó giữ `fullScreenCover` của Reader. `userInfo` mang đủ trường của `ShelfReaderRoute`.
    static let openReaderFromNotification = Notification.Name("openReaderFromNotification")
}
