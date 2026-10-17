import SwiftUI
import UIKit

/// Presenter toàn cục **mở lại** trình phát gắn với `VideoPlaybackSession` đang chạy — từ mục Video của hub
/// (`VideoMiniPlayerState.onReopen`) hoặc khi khôi phục từ PiP.
///
/// Cách tìm chỗ trình bày giống `VisibleBrowserTabManager.reopenContainer`: chỉ nhận window level `.normal` (widget TTS
/// và hub nổi sống ở window riêng level cao hơn — trình bày lên đó thì sheet biến mất theo window), lấy VC trên cùng
/// của chuỗi `presentedViewController`, đang chuyển cảnh thì thử lại sau 0,3 giây.
@MainActor
final class VideoPlayerPresenter {
    static let shared = VideoPlayerPresenter()

    private weak var hostController: UIViewController?
    private static let maxRetryCount = 6

    private init() {}

    /// Gắn handler vào session. Gọi mỗi lần màn trình phát xuất hiện (rẻ, idempotent).
    static func install() {
        VideoPlaybackSession.shared.presentScreenHandler = { completion in
            VideoPlayerPresenter.shared.presentPlayer(retryCount: 0, completion: completion)
        }
    }

    private func presentPlayer(retryCount: Int, completion: @escaping () -> Void) {
        let session = VideoPlaybackSession.shared
        guard session.isActive, !session.isScreenAttached else {
            completion()
            return
        }
        if let host = hostController, host.presentingViewController != nil, !host.isBeingDismissed {
            completion()
            return
        }
        guard let top = Self.findTopViewController() else {
            AppLogger.shared.log("❌ [VideoPlayer] Không tìm được màn để mở lại trình phát")
            completion()
            return
        }
        if top.isBeingPresented || top.isBeingDismissed {
            guard retryCount < Self.maxRetryCount else {
                AppLogger.shared.log("❌ [VideoPlayer] Mở lại trình phát thất bại: màn trên cùng đang chuyển cảnh quá lâu")
                completion()
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    VideoPlayerPresenter.shared.presentPlayer(retryCount: retryCount + 1, completion: completion)
                }
            }
            return
        }

        let host = VideoPlayerHostingController(rootView: AnyView(EmptyView()))
        host.modalPresentationStyle = .fullScreen
        host.view.backgroundColor = .black
        let screen = VideoPlayerScreen(onDismiss: { [weak host] in
            host?.dismiss(animated: true)
        })
        if let container = session.modelContainer {
            host.rootView = AnyView(screen.modelContainer(container))
        } else {
            host.rootView = AnyView(screen)
        }
        hostController = host
        AppLogger.shared.log("🎬 [VideoPlayer] Mở lại trình phát từ phiên đang chạy")
        top.present(host, animated: true) {
            completion()
        }
    }

    private static func findTopViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let windowScene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first else {
            return nil
        }
        let hostWindows = windowScene.windows.filter { $0.windowLevel == .normal && !$0.isHidden }
        guard let window = hostWindows.first(where: { $0.isKeyWindow })
                ?? hostWindows.first
                ?? windowScene.windows.first(where: { $0.windowLevel == .normal }),
              let rootVC = window.rootViewController else {
            return nil
        }
        var topVC = rootVC
        while let presented = topVC.presentedViewController {
            topVC = presented
        }
        return topVC
    }
}
