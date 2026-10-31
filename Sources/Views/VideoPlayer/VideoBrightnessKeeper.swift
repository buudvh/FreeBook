import UIKit

/// Chủ **duy nhất** của việc đổi độ sáng màn hình ở trình phát phim.
///
/// Một mức chung cho mọi phim, mọi nguồn: mức cuối người dùng vuốt chỉnh (`VideoGestureView`), lưu ở UserDefaults.
/// - Màn phim hiện (`VideoPlayerScreen.onAppear`) ⇒ chụp độ sáng của máy **rồi** áp mức đã nhớ. Chưa từng vuốt ⇒ không đụng.
/// - Rời màn (đóng / thu nhỏ / PiP) hoặc app mất active ⇒ trả độ sáng của máy (độ sáng là của cả máy, iOS không tự trả).
/// - Active lại khi màn còn mở ⇒ chụp lại (người dùng có thể vừa chỉnh ở Trung tâm điều khiển) rồi áp lại.
///
/// Chụp độ sáng gốc chỉ ở đây: nếu cử chỉ tự chụp lần nữa thì nó sẽ chụp nhầm mức của phim làm "gốc".
@MainActor
final class VideoBrightnessKeeper {
    static let shared = VideoBrightnessKeeper()

    /// Khoá UserDefaults — không dấu chấm.
    private static let savedLevelKey = "videoPlayerBrightness"

    /// Màn phim đang hiện (giữa `activate` và `deactivate`) — tập như `VideoPlaybackSession.attachedScreens`: màn mới có
    /// thể hiện trước khi màn cũ kịp `onDisappear` (mở lại từ hub / PiP) ⇒ chỉ trả độ sáng khi màn **cuối cùng** rời đi.
    private var owners = Set<ObjectIdentifier>()
    /// Độ sáng của máy trước khi trình phát đổi (kèm màn hình đã đổi); `nil` = chưa đổi hoặc đã trả lại.
    private var original: (screen: UIScreen, value: CGFloat)?
    /// Mức cử chỉ vừa đặt, lưu khi nhả tay.
    private var pendingLevel: CGFloat?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    /// Mức đã nhớ; `nil` = chưa từng vuốt chỉnh (0 vẫn là mức hợp lệ nên phải tra `object(forKey:)`).
    private static var savedLevel: CGFloat? {
        guard let value = UserDefaults.standard.object(forKey: savedLevelKey) as? Double else { return nil }
        return CGFloat(min(1, max(0, value)))
    }

    // MARK: - Vòng đời màn phim

    func activate(_ owner: AnyObject) {
        let wasActive = !owners.isEmpty
        owners.insert(ObjectIdentifier(owner))
        guard !wasActive else { return }
        applySavedLevel()
    }

    /// Gỡ màn không có trong tập (gọi lặp) thì bỏ qua.
    func deactivate(_ owner: AnyObject) {
        guard owners.remove(ObjectIdentifier(owner)) != nil, owners.isEmpty else { return }
        pendingLevel = nil
        restoreOriginal()
    }

    // MARK: - Cử chỉ

    /// Vuốt chỉnh: đặt ngay theo tay (chụp độ sáng của máy nếu chưa chụp).
    func setLevel(_ level: CGFloat, on screen: UIScreen) {
        rememberOriginal(of: screen)
        screen.brightness = level
        pendingLevel = level
    }

    /// Nhả tay: nhớ mức vừa đặt cho lần mở phim sau. Cử chỉ bị huỷ thì vẫn lưu mức cuối đã đặt (màn đang sáng đúng
    /// mức đó), không lưu giá trị 0 mà cử chỉ báo khi huỷ.
    func commitLevel() {
        guard let level = pendingLevel else { return }
        pendingLevel = nil
        UserDefaults.standard.set(Double(level), forKey: Self.savedLevelKey)
    }

    // MARK: - App active / mất active

    @objc private func handleWillResignActive() {
        restoreOriginal()
    }

    @objc private func handleDidBecomeActive() {
        guard !owners.isEmpty else { return }
        applySavedLevel()
    }

    // MARK: - Độ sáng

    private func applySavedLevel() {
        guard let level = Self.savedLevel, let screen = Self.activeScreen else { return }
        rememberOriginal(of: screen)
        screen.brightness = level
    }

    private func rememberOriginal(of screen: UIScreen) {
        guard original == nil else { return }
        original = (screen: screen, value: screen.brightness)
    }

    private func restoreOriginal() {
        guard let original else { return }
        self.original = nil
        original.screen.brightness = original.value
    }

    private static var activeScreen: UIScreen? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first(where: { $0.activationState == .foregroundActive })
            ?? scenes.first(where: { $0.activationState == .foregroundInactive })
        return scene?.screen
    }
}
