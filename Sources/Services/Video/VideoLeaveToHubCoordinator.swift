import Foundation
import UIKit

/// **Thu phim vào hub** theo luật chung — nút Home của màn xem, tắt công tắc NSFW lúc đang phát phim 18+
/// (`VideoPlaybackSession+NsfwGuard`) và rời app (`VideoLeaveAppPolicy`). Không bao giờ dừng / tạm dừng phim.
///
/// ## Xin thu vào hub (`collapseToHub`)
/// Tầng dịch vụ không đóng được màn ⇒ màn xem (`VideoPlayerScreen`, khoá = controller của màn) và cửa sổ nhỏ
/// (`VideoMiniPlayerWindowManager`) đăng ký `CollapseHandler` (`register` / `unregister`); coordinator gọi lần lượt. Màn đang
/// rời (`isLeaving`) / không sở hữu phiên, cửa sổ đã ẩn ⇒ tự bỏ qua, nên xin lặp là an toàn (Home tắt NSFW ⇒ guard NSFW
/// xin thu thêm một lần nữa).
///
/// ## Luật chung của Home / rời app (`applyLeaveRules`)
/// Phim **đang phát** là 18+ (`RepositoryFilterPolicy.isNsfwBook`) ⇒ tắt tiếng nếu `VideoMutePolicy.shouldStartMuted`
/// (chỉ tắt, không bao giờ bật lại tiếng); công tắc NSFW đang bật ⇒ tắt. Không cần `VideoWatchModel` (phim ở cửa sổ nhỏ /
/// hub vẫn dùng được). Không toast, không SwiftUI.
///
/// ## Rời app (`installAppLeaveObserver`)
/// App **vào nền** (`didEnterBackgroundNotification`: khoá màn hình, vuốt về màn hình chính — **không** dùng `.inactive`:
/// kéo Trung tâm điều khiển cũng ra inactive), công tắc bật, phiên đang có phim ⇒ thu màn xem / cửa sổ nhỏ vào hub
/// **không hiệu ứng** (đang ở nền, completion của animation có thể không bao giờ chạy), rồi luật chung; công tắc NSFW vừa
/// được tắt ⇒ về trang gốc Khám phá — sau khi màn xem đã đóng hẳn (`then`), hoặc ngay nếu không có màn nào nhận. Kênh
/// chuyển tab thuộc tầng View nên `VideoPlayerPresenter.install` cấp closure. Gọi lặp an toàn (màn đang rời / đã ở hub
/// tự bỏ qua, tắt tiếng / tắt NSFW lặp lại không đổi gì).
@MainActor
final class VideoLeaveToHubCoordinator {
    enum Reason {
        /// Tắt công tắc NSFW lúc đang phát phim 18+.
        case nsfwTurnedOff
        /// App vào nền, công tắc `VideoLeaveAppPolicy` bật — thu không hiệu ứng.
        case appBackground

        var logLabel: String {
            switch self {
            case .nsfwTurnedOff: return "tắt NSFW"
            case .appBackground: return "rời app"
            }
        }
    }

    /// Trả `true` khi chủ **nhận** chạy `then` sau khi đã đóng hẳn (màn xem: `leave(then:)`); `false` = không nhận / bỏ qua.
    typealias CollapseHandler = (_ reason: Reason, _ then: (() -> Void)?) -> Bool

    static let shared = VideoLeaveToHubCoordinator()

    private var handlers: [ObjectIdentifier: CollapseHandler] = [:]
    /// Về trang gốc tab Khám phá — tầng View cấp (`VideoPlayerPresenter.install`).
    private var showDiscoveryRoot: (() -> Void)?
    private var backgroundObserver: NSObjectProtocol?
    /// Đọc lười (không trong `init`): session có thể gọi tới coordinator ngay trong lúc nó đang khởi tạo.
    private var session: VideoPlaybackSession { VideoPlaybackSession.shared }

    private init() {}

    // MARK: - Đăng ký

    func register(_ owner: AnyObject, handler: @escaping CollapseHandler) {
        handlers[ObjectIdentifier(owner)] = handler
    }

    func unregister(_ owner: AnyObject) {
        handlers.removeValue(forKey: ObjectIdentifier(owner))
    }

    // MARK: - Thu vào hub

    /// Xin mọi màn / cửa sổ nhỏ đang hiện phiên thu phim vào hub. `then` trao cho chủ **đầu tiên** nhận nó (chạy sau khi
    /// màn đã đóng); trả `true` khi có chủ nhận — không ai nhận thì chỗ gọi tự chạy việc tiếp theo.
    @discardableResult
    func collapseToHub(reason: Reason, then: (() -> Void)? = nil) -> Bool {
        var pending = then
        var accepted = false
        // Chép ra trước: cửa sổ nhỏ tự `unregister` lúc ẩn ngay trong handler.
        for handler in Array(handlers.values) {
            guard handler(reason, pending) else { continue }
            accepted = true
            pending = nil
        }
        return accepted
    }

    // MARK: - Luật chung

    /// Phần dịch vụ của nút Home (View lo đóng màn + chuyển tab): phim 18+ đang phát ⇒ tắt tiếng theo `VideoMutePolicy`;
    /// công tắc NSFW đang bật ⇒ tắt (guard NSFW của phiên sẽ xin thu phim vào hub — chỗ gọi phải rời màn **trước**). Trả
    /// `true` khi công tắc NSFW vừa được tắt ở đây.
    @discardableResult
    func applyLeaveRules(source: String) -> Bool {
        if let playing = session.launch,
           RepositoryFilterPolicy.isNsfwBook(bookId: playing.bookId, packageId: playing.extensionPackageId) {
            let policy = VideoMutePolicy.current.title
            if VideoMutePolicy.shouldStartMuted(bookId: playing.bookId, packageId: playing.extensionPackageId) {
                AppLogger.shared.log("🔞 [VideoLeave] \(source): phim 18+ ⇒ tắt tiếng theo «\(policy)»")
                session.setMuted(true)
            } else {
                AppLogger.shared.log("🔞 [VideoLeave] \(source): phim 18+, tuỳ chọn «\(policy)» ⇒ giữ tiếng")
            }
        }
        guard RepositoryFilterPolicy.includesNsfwPreference else { return false }
        AppLogger.shared.log("🔞 [VideoLeave] \(source): tắt công tắc NSFW")
        UserDefaults.standard.set(false, forKey: RepositoryFilterPolicy.includeNsfwDefaultsKey)
        return true
    }

    // MARK: - Rời app

    /// Gắn theo dõi vào nền (một lần) + cách về Khám phá. `VideoPlayerPresenter.install` gọi mỗi lần màn trình phát xuất
    /// hiện — phiên chỉ có phim sau khi một màn trình phát đã hiện trong tiến trình này.
    func installAppLeaveObserver(showDiscoveryRoot: @escaping () -> Void) {
        self.showDiscoveryRoot = showDiscoveryRoot
        guard backgroundObserver == nil else { return }
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                VideoLeaveToHubCoordinator.shared.handleAppDidEnterBackground()
            }
        }
    }

    private func handleAppDidEnterBackground() {
        guard session.isActive else { return }
        guard VideoLeaveAppPolicy.isEnabled else {
            AppLogger.shared.log("🎬 [VideoLeave] Rời app: công tắc thu vào hub đang tắt ⇒ giữ nguyên, phim chỉ phát tiếng")
            return
        }
        // Chụp trước: `applyLeaveRules` sẽ tắt công tắc này.
        let turnsOffNsfw = RepositoryFilterPolicy.includesNsfwPreference
        AppLogger.shared.log("🎬 [VideoLeave] Rời app ⇒ thu phim vào hub (không dừng)\(turnsOffNsfw ? ", tắt NSFW rồi về Khám phá" : "")")
        let navigate: (() -> Void)? = turnsOffNsfw
            ? { VideoLeaveToHubCoordinator.shared.navigateToDiscoveryRoot() }
            : nil
        // Thu TRƯỚC khi tắt NSFW: guard NSFW xin thu lần nữa thì màn đã `isLeaving` / cửa sổ đã ẩn ⇒ không chạy hiệu ứng bay.
        let deferred = collapseToHub(reason: .appBackground, then: navigate)
        applyLeaveRules(source: "Rời app")
        if !deferred {
            navigate?()
        }
    }

    private func navigateToDiscoveryRoot() {
        guard let showDiscoveryRoot else {
            AppLogger.shared.log("❌ [VideoLeave] Chưa có kênh chuyển tab ⇒ không về được Khám phá")
            return
        }
        AppLogger.shared.log("🔞 [VideoLeave] Rời app ⇒ về trang gốc Khám phá")
        showDiscoveryRoot()
    }
}
