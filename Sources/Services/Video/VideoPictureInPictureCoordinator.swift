import Foundation
import AVKit
import AVFoundation

/// Bọc `AVPictureInPictureController` gắn với `AVPlayerLayer` của `VideoPlaybackSession`.
///
/// - Rời app khi đang xem (màn hình đang hiện, phim đang phát) thì PiP **tự bật**
///   (`canStartPictureInPictureAutomaticallyFromInline`, lựa chọn của người dùng).
/// - Khôi phục từ PiP: hỏi session qua `onRestoreRequest`; session mở lại trình phát rồi mới gọi `completion(true)`.
///
/// AVKit không cam kết luồng gọi delegate ⇒ mọi callback chuyển về main rồi mới chạm trạng thái hoặc gọi closure.
/// Class không gắn `@MainActor` để khớp mọi kiểu khai báo delegate của SDK; trạng thái chỉ được đọc/ghi trên main.
final class VideoPictureInPictureCoordinator: NSObject, AVPictureInPictureControllerDelegate {
    /// `isPictureInPicturePossible` đổi (KVO, có giá trị ban đầu).
    var onPossibleChange: (@MainActor (Bool) -> Void)?
    /// PiP bắt đầu (`true`, từ lúc *sắp* bật) / đã tắt hẳn (`false`).
    var onActiveChange: (@MainActor (Bool) -> Void)?
    /// PiP đã bật xong (`didStart`) — màn hình dùng để tự thu nhỏ khi người dùng bấm PiP lúc app đang mở.
    var onDidStart: (@MainActor () -> Void)?
    /// Người dùng bấm "khôi phục" trên cửa sổ PiP. Closure nhận completion của AVKit, phải gọi đúng một lần.
    var onRestoreRequest: (@MainActor (@escaping (Bool) -> Void) -> Void)?

    private let controller: AVPictureInPictureController
    private var possibleObservation: NSKeyValueObservation?
    /// Từ `willStart` tới `didStart`/`failedToStart`: PiP đang bật dở — lúc vào nền chưa được tách hình khỏi player.
    private(set) var isStarting = false

    /// `nil` khi máy không hỗ trợ PiP.
    init?(playerLayer: AVPlayerLayer) {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return nil }
        // Gán qua kiểu Optional: đúng dù SDK khai initializer này failable hay không.
        let made: AVPictureInPictureController? = AVPictureInPictureController(playerLayer: playerLayer)
        guard let made else { return nil }
        controller = made
        super.init()
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] pip, _ in
            // Chụp `self` (weak) vào hằng trước khi đưa sang closure khác — không tham chiếu biến `weak var` bắt được.
            let owner = self
            let possible = pip.isPictureInPicturePossible
            Self.onMain {
                owner?.onPossibleChange?(possible)
            }
        }
    }

    var isActive: Bool { controller.isPictureInPictureActive }
    var isActiveOrStarting: Bool { isStarting || controller.isPictureInPictureActive }
    var isPossible: Bool { controller.isPictureInPicturePossible }

    func toggle() {
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
        } else if controller.isPictureInPicturePossible {
            controller.startPictureInPicture()
        } else {
            AppLogger.shared.log("⚠️ [VideoPiP] Chưa bật được PiP (player chưa sẵn sàng hoặc hệ thống không cho)")
        }
    }

    func stop() {
        guard controller.isPictureInPictureActive else { return }
        controller.stopPictureInPicture()
    }

    // MARK: - AVPictureInPictureControllerDelegate

    func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Self.onMain { [weak self] in
            self?.isStarting = true
            self?.onActiveChange?(true)
        }
    }

    func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Self.onMain { [weak self] in
            self?.isStarting = false
            AppLogger.shared.log("🖼️ [VideoPiP] Đã bật PiP")
            self?.onDidStart?()
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        failedToStartPictureInPictureWithError error: Error
    ) {
        let message = error.localizedDescription
        Self.onMain { [weak self] in
            self?.isStarting = false
            AppLogger.shared.log("❌ [VideoPiP] Không bật được PiP: \(message)")
            self?.onActiveChange?(false)
        }
    }

    func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Self.onMain { [weak self] in
            self?.isStarting = false
            AppLogger.shared.log("🖼️ [VideoPiP] Đã tắt PiP")
            self?.onActiveChange?(false)
        }
    }

    func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Self.onMain { [weak self] in
            guard let handler = self?.onRestoreRequest else {
                completionHandler(false)
                return
            }
            handler(completionHandler)
        }
    }

    // MARK: - Luồng

    private static func onMain(_ body: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                body()
            }
        } else {
            Task { @MainActor in
                body()
            }
        }
    }
}
