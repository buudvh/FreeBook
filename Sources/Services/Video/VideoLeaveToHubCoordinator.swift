import Foundation

/// **Thu phim vào hub** theo luật chung — nút Home của màn xem, tắt công tắc NSFW lúc đang phát phim 18+
/// (`VideoPlaybackSession+NsfwGuard`). Không bao giờ dừng / tạm dừng phim.
///
/// ## Xin thu vào hub (`collapseToHub`)
/// Tầng dịch vụ không đóng được màn ⇒ màn xem (`VideoPlayerScreen`, khoá = controller của màn) và cửa sổ nhỏ
/// (`VideoMiniPlayerWindowManager`) đăng ký `CollapseHandler` (`register` / `unregister`); coordinator gọi lần lượt. Màn đang
/// rời (`isLeaving`) / không sở hữu phiên, cửa sổ đã ẩn ⇒ tự bỏ qua, nên xin lặp là an toàn (Home tắt NSFW ⇒ guard NSFW
/// xin thu thêm một lần nữa).
///
/// ## Luật chung của Home (`applyLeaveRules`)
/// Phim **đang phát** là 18+ (`RepositoryFilterPolicy.isNsfwBook`) ⇒ tắt tiếng nếu `VideoMutePolicy.shouldStartMuted`
/// (chỉ tắt, không bao giờ bật lại tiếng); công tắc NSFW đang bật ⇒ tắt. Không cần `VideoWatchModel` (phim ở cửa sổ nhỏ /
/// hub vẫn dùng được). Không toast, không SwiftUI.
@MainActor
final class VideoLeaveToHubCoordinator {
    enum Reason {
        /// Tắt công tắc NSFW lúc đang phát phim 18+.
        case nsfwTurnedOff

        var logLabel: String {
            switch self {
            case .nsfwTurnedOff: return "tắt NSFW"
            }
        }
    }

    /// Trả `true` khi chủ **nhận** chạy `then` sau khi đã đóng hẳn (màn xem: `leave(then:)`); `false` = không nhận / bỏ qua.
    typealias CollapseHandler = (_ reason: Reason, _ then: (() -> Void)?) -> Bool

    static let shared = VideoLeaveToHubCoordinator()

    private var handlers: [ObjectIdentifier: CollapseHandler] = [:]
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
}
