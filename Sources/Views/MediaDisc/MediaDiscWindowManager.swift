import Combine
import SwiftData
import UIKit

/// Điều phối **đĩa nghe góc dưới phải** (1.3.808) — một đĩa xoay tròn dùng chung cho trình nghe nhạc và TTS (kiểu widget
/// "Đĩa góc dưới"), nổi trên mọi màn (trang gốc tab, trang đẩy vào, sheet, trình duyệt, Reader) ở cửa sổ lớp phủ riêng
/// (`MediaDiscWindow`, level `alert − 1.75`: trên nút hub `−2`, dưới ngăn kéo `…` `−1.5`, widget TTS `−1` và toast). Thay
/// thanh nghe nhạc mini, kiểu "Thanh nghe nhạc" của widget TTS và hai nút đĩa riêng của Reader.
///
/// - **Nguồn** (`kind`): trình nghe có album ⇒ nhạc; không thì TTS có phiên + kiểu "Đĩa góc dưới" ⇒ TTS; chờ cổng từ điển
///   mở như các cửa sổ nổi khác. Có nguồn ⇒ dựng/hiện cửa sổ; hết nguồn hoặc phim toàn màn ⇒ (đóng sheet,) thu đĩa rồi ẩn
///   cửa sổ.
/// - **Được hiện** (`isDiscAllowed`): bàn phím ẩn, không phim toàn màn (`FloatingWidgetSuppression`), màn nghe không hiện.
///   Chỗ đứng + màn trên cùng (màn xem phim, hộp thoại) do container xét qua `MediaDiscPlacement`.
/// - **Tính lại chỗ**: neo vào/rời (`MediaDiscAnchorRegistry`), bàn phím, xoay màn, đổi trạng thái — cộng một lượt hỏi nhẹ
///   0,4 s chỉ khi cửa sổ đang hiện và app không ở nền (đóng một sheet không có neo thì trang bên dưới không phát sự kiện
///   nào; trang con của `TabView` dạng trang cũng vậy).
/// - Dòng báo của trình nghe (`AudioPlaybackNotice`: "Tự sang: <tên>", "Bỏ qua …") trước nằm trên thanh mini ⇒ nay là
///   **toast** khi màn nghe không hiện (màn nghe vẫn có dải báo riêng).
/// - Sheet Hẹn giờ TTS mở Reader (`openCurrentlyPlayingReader`) từ trong sheet của đĩa ⇒ đóng hết sheet của đĩa, kẻo Reader
///   mở ở cửa sổ chính mà vẫn bị sheet che.
///
/// ## Hai chỗ đặt đĩa (1.3.812)
/// - **Trang gốc các tab** (có `.mainTabBar()`): đĩa 32 pt ở ô giữa của `MainTabBar` (`MediaDiscTabBarSlot`, theo `kind` —
///   biết ngay từ khung đầu). Thanh tab là neo `.hostsDisc` ⇒ đĩa góc ẩn **ngay** khi màn trên cùng có thanh tab.
/// - **Mọi màn khác**: đĩa góc dưới phải như trên; hiện lại sau khi màn trên cùng thôi có thanh tab ~0,3 s (chống lóe lúc
///   đẩy trang). Nhấn giữ đĩa góc ⇒ tạm lên góc phải vùng header 5 giây (container).
/// - Chạm đĩa ở đâu cũng `presentQuickControls()` ⇒ sheet điều khiển nhanh trình bày từ cửa sổ này (`MediaDiscSheetHost`).
@MainActor
final class MediaDiscWindowManager: ObservableObject {
    static let shared = MediaDiscWindowManager()

    /// Nguồn hiện tại; `nil` ⇒ không có đĩa.
    @Published private(set) var kind: MediaDiscKind?
    /// Nguồn của mặt đĩa — giữ nguồn cuối cùng khi `kind` về `nil` để đĩa thu lại vẫn còn bìa.
    @Published private(set) var faceKind: MediaDiscKind = .music
    /// Đĩa đang thật sự hiện trên màn và app không ở nền — bìa chỉ xoay khi `true`.
    @Published private(set) var isDiscOnScreen = false
    /// Tăng mỗi lần cần đóng mọi sheet đang mở từ đĩa.
    @Published private(set) var closeSheetsToken = 0
    /// Tăng mỗi lần đĩa (góc hay ô giữa thanh tab) xin mở sheet điều khiển nhanh — `MediaDiscSheetHost` nghe.
    @Published private(set) var presentRequestToken = 0
    /// App không ở nền — bìa đĩa ở thanh tab chỉ xoay khi `true`.
    @Published private(set) var isAppActive = true

    var modelContainer: ModelContainer?

    private var window: MediaDiscWindow?
    private var container: MediaDiscContainerViewController?
    private var isKeyboardVisible = false
    private var isHideScheduled = false
    private var cancellables = Set<AnyCancellable>()

    private static let hideDelay: TimeInterval = 0.3

    private init() {
        isAppActive = UIApplication.shared.applicationState != .background
        let mini = AudioMiniPlayerState.shared
        // `@Published` phát ở willSet ⇒ đọc lại ở lượt sau (`receive(on:)`).
        mini.$isActive
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)
        mini.$isScreenPresented
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.container?.updateDisc(animated: true) }
            .store(in: &cancellables)
        TTSWidgetPreferences.shared.$style
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)
        // Phim toàn màn / khoá màn ⇒ ẩn hẳn cửa sổ như hub và widget TTS (cửa sổ phủ kín màn không được dính tới thanh
        // trạng thái / hướng xoay của trình phát).
        FloatingWidgetSuppression.shared.$isSuppressed
            .removeDuplicates()
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshState() }
            .store(in: &cancellables)
        // Giá trị được phát ra là chữ mới (`show` ghi chữ rồi tự về `nil` sau 5 giây).
        AudioPlaybackNotice.shared.$text
            .sink { [weak self] text in self?.showNoticeToast(text) }
            .store(in: &cancellables)
        observeNotifications()
    }

    // MARK: - Trạng thái

    /// Đọc lại nguồn rồi hiện / ẩn cửa sổ. `FreeBookApp` gọi lúc mở app, khi cổng từ điển mở và khi TTS bật/tắt phiên;
    /// trình nghe và kiểu widget thì manager tự nghe.
    func refreshState() {
        let newKind = Self.resolveKind()
        if newKind != kind {
            if kind != nil { requestCloseSheets() }
            kind = newKind
            if let newKind, faceKind != newKind { faceKind = newKind }
            AppLogger.shared.log("💿 [MediaDisc] Nguồn đĩa: \(newKind?.rawValue ?? "không")")
        }
        if isWindowWanted {
            showWindow()
        } else {
            scheduleHide()
        }
        container?.updateDisc(animated: true)
    }

    /// Cửa sổ của đĩa nên hiện: có nguồn và không có phim toàn màn.
    private var isWindowWanted: Bool {
        kind != nil && !FloatingWidgetSuppression.shared.isSuppressed
    }

    /// Đĩa được phép hiện (chưa xét neo / màn trên cùng).
    var isDiscAllowed: Bool {
        kind != nil
            && !isKeyboardVisible
            && !FloatingWidgetSuppression.shared.isSuppressed
            && !AudioMiniPlayerState.shared.isScreenPresented
    }

    /// Chạm đĩa (góc hoặc ô giữa thanh tab) ⇒ mở sheet điều khiển nhanh ở cửa sổ của đĩa. Cửa sổ có mặt mỗi khi có nguồn
    /// (kể cả lúc đĩa góc đang ẩn vì màn có thanh tab).
    func presentQuickControls() {
        guard kind != nil, let window, !window.isHidden else { return }
        presentRequestToken &+= 1
    }

    /// Sheet điều khiển nhanh vừa đóng ⇒ đĩa đang tạm đứng ở header về chỗ.
    func quickControlsDidDismiss() {
        container?.endElevation(animated: true)
    }

    /// Container báo đĩa đang hiện / đã ẩn. Ghi ở nhịp main sau — có thể được gọi giữa lượt layout.
    func noteDiscShown(_ shown: Bool) {
        let value = shown && isAppActive
        guard value != isDiscOnScreen else { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isDiscOnScreen != value else { return }
                self.isDiscOnScreen = value
            }
        }
    }

    private static func resolveKind() -> MediaDiscKind? {
        guard TranslationManager.shared.isInitialized else { return nil }
        if AudioMiniPlayerState.shared.isActive { return .music }
        if TTSManager.shared.showFloatingWidget, TTSWidgetPreferences.shared.style == .cornerDisc { return .tts }
        return nil
    }

    private func requestCloseSheets() {
        guard container?.presentedViewController != nil else { return }
        closeSheetsToken &+= 1
    }

    private func showNoticeToast(_ text: String?) {
        guard let text, !text.isEmpty, !AudioMiniPlayerState.shared.isScreenPresented else { return }
        ToastManager.shared.show(message: text, type: .info, recordsInInbox: false)
    }

    // MARK: - Cửa sổ

    private func showWindow() {
        guard let scene = AppMainWindowScene.current() else { return }
        if let window {
            move(to: scene)
            if window.isHidden {
                window.isHidden = false
                container?.windowDidShow()
            }
        } else {
            let controller = MediaDiscContainerViewController()
            let win = MediaDiscWindow(windowScene: scene)
            win.windowLevel = UIWindow.Level(rawValue: UIWindow.Level.alert.rawValue - 1.75)
            win.backgroundColor = .clear
            win.containerViewController = controller
            win.rootViewController = controller
            window = win
            container = controller
            // Không bao giờ `makeKeyAndVisible()`: cửa sổ lớp phủ không được giành key của cửa sổ chính.
            win.isHidden = false
            controller.windowDidShow()
        }
        updatePolling()
    }

    /// Thu đĩa (container tự chạy hiệu ứng) rồi mới ẩn cửa sổ; sheet đang mở thì chờ nó đóng xong.
    private func scheduleHide() {
        guard let window, !window.isHidden, !isHideScheduled else { return }
        isHideScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hideDelay) { [weak self] in
            MainActor.assumeIsolated { self?.finishHide() }
        }
    }

    private func finishHide() {
        isHideScheduled = false
        guard !isWindowWanted, let window, !window.isHidden else { return }
        if container?.presentedViewController != nil {
            requestCloseSheets()
            scheduleHide()
            return
        }
        window.isHidden = true
        container?.windowDidHide()
        updatePolling()
    }

    private func updatePolling() {
        let visible = window.map { !$0.isHidden } ?? false
        container?.setPolling(visible && isAppActive)
    }

    private func move(to scene: UIWindowScene) {
        guard let window, window.windowScene !== scene else { return }
        AppLogger.shared.log("💿 [MediaDisc] Chuyển đĩa sang scene: \(AppMainWindowScene.describe(scene))")
        window.windowScene = scene
        container?.view.setNeedsLayout()
    }

    // MARK: - Thông báo hệ thống

    private func observeNotifications() {
        let center = NotificationCenter.default
        let observed: [(Selector, Notification.Name)] = [
            (#selector(keyboardWillShow), UIResponder.keyboardWillShowNotification),
            (#selector(keyboardWillHide), UIResponder.keyboardWillHideNotification),
            (#selector(appDidEnterBackground), UIApplication.didEnterBackgroundNotification),
            (#selector(appWillEnterForeground), UIApplication.willEnterForegroundNotification),
            (#selector(sceneDidActivate(_:)), UIScene.didActivateNotification),
            (#selector(sceneDidDisconnect(_:)), UIScene.didDisconnectNotification)
        ]
        for (selector, name) in observed {
            center.addObserver(self, selector: selector, name: name, object: nil)
        }
        center.addObserver(
            self,
            selector: #selector(openCurrentlyPlayingReader),
            name: NSNotification.Name("openCurrentlyPlayingReader"),
            object: nil
        )
    }

    @objc private func keyboardWillShow() {
        guard !isKeyboardVisible else { return }
        isKeyboardVisible = true
        container?.updateDisc(animated: true)
    }

    @objc private func keyboardWillHide() {
        guard isKeyboardVisible else { return }
        isKeyboardVisible = false
        container?.updateDisc(animated: true)
    }

    @objc private func appDidEnterBackground() {
        isAppActive = false
        updatePolling()
        noteDiscShown(false)
    }

    @objc private func appWillEnterForeground() {
        isAppActive = true
        updatePolling()
        container?.updateDisc(animated: false)
    }

    /// Chỉ theo scene chứa giao diện chính (`AppMainWindowScene`) — scene của PiP cũng báo `didActivate`.
    @objc private func sceneDidActivate(_ notification: Notification) {
        guard kind != nil, let scene = notification.object as? UIWindowScene,
              AppMainWindowScene.isMainInterface(scene) else { return }
        move(to: scene)
    }

    /// Scene đang giữ đĩa bị ngắt ⇒ đưa đĩa về scene chính ở lượt sau.
    @objc private func sceneDidDisconnect(_ notification: Notification) {
        guard let window, let scene = notification.object as? UIScene else { return }
        guard window.windowScene == nil || window.windowScene === scene else { return }
        if let target = AppMainWindowScene.current(excluding: scene) {
            move(to: target)
        }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refreshState() }
        }
    }

    /// Reader sắp mở ở cửa sổ chính (sheet Hẹn giờ TTS, hub…) ⇒ sheet của đĩa không được che nó.
    ///
    /// Chờ một nhịp (1.3.809): lối hay gặp là chọn chương ở sheet Hẹn giờ TTS — sheet **lớp hai** đè lên sheet điều khiển
    /// nhanh, đang tự đóng. Đóng sheet cha ngay lúc sheet con còn đang trượt xuống thì UIKit có thể bỏ qua lệnh, sheet nhanh
    /// kẹt lại che Reader. Đợi sheet con đóng xong (~0,35 s) rồi mới đóng.
    @objc private func openCurrentlyPlayingReader() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.closeSheetsAfterChildDelay) { [weak self] in
            MainActor.assumeIsolated { self?.requestCloseSheets() }
        }
    }

    private static let closeSheetsAfterChildDelay: TimeInterval = 0.45
}
