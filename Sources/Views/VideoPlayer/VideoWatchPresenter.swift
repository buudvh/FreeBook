import SwiftData
import SwiftUI
import UIKit

/// Mở **màn xem phim** (`VideoPlayerScreen(watch:onDismiss:)`) từ mọi lối vào phim (Khám phá, Tìm, Thể loại, Đề xuất…)
/// và khi mở lại trình phát từ hub / PiP (`VideoPlayerPresenter` chuyển sang đây).
///
/// Trình bày bằng UIKit `.overFullScreen` như `VideoPlayerPresenter` (cùng `VideoPlayerHostingController`, cùng cách tìm
/// VC trên cùng): màn bên dưới vẫn sống, và trình phát **không** nằm trong `NavigationStack` — đẩy một màn khác lên
/// stack (đề xuất, thể loại, đổi nguồn, đổi tab) sẽ làm màn trình phát "biến mất" ⇒ tự thu nhỏ.
///
/// - `present`: màn xem đang mở thì đóng nó trước rồi mới mở màn mới — không bao giờ chồng hai màn xem (kể cả lúc màn
///   đang hiện bìa phim B mà hub mở lại phim A đang chạy nền).
/// - Trang phụ của màn xem (thể loại, Xem thêm, Chi tiết của đề xuất) không còn ở đây: từ 1.3.744 là trang toàn màn đè
///   lên màn xem (`VideoWatchPagePresenter`, dùng chung `readyTopViewController`).
@MainActor
final class VideoWatchPresenter {
    static let shared = VideoWatchPresenter()

    private weak var hostController: UIViewController?
    /// Màn xem đang hiện trong `fullScreenCover` của router (`VideoWatchRouteView`) — không do presenter này trình bày.
    private weak var coverModel: VideoWatchModel?
    private static let maxRetryCount = 6

    private init() {}

    static func present(_ request: VideoWatchRequest, modelContainer: ModelContainer, completion: (() -> Void)? = nil) {
        shared.present(request, container: modelContainer, retryCount: 0, completion: completion)
    }

    /// Mở lại phim đang chạy (hub / PiP). Màn xem của router đang hiện bìa phim khác ⇒ đổi chính màn đó sang phim đang
    /// chạy (`replace`), không trình bày thêm một màn chồng lên; còn lại ⇒ `present`.
    static func presentRunningSession(_ launch: BookContentLaunch, modelContainer: ModelContainer, completion: @escaping () -> Void) {
        let request = VideoWatchRequest(launch: launch)
        if let model = shared.coverModel, !model.ownsSession {
            AppLogger.shared.log("🎬 [VideoWatch] Màn xem trong cover đang hiện bìa ⇒ đổi sang phim đang chạy")
            model.replace(with: request)
            completion()
            return
        }
        present(request, modelContainer: modelContainer, completion: completion)
    }

    /// `VideoPlayerScreen` của router báo hiện / ẩn (chỉ màn không do presenter trình bày).
    static func noteCoverScreen(_ model: VideoWatchModel, isVisible: Bool) {
        if isVisible {
            shared.coverModel = model
        } else if shared.coverModel === model {
            shared.coverModel = nil
        }
    }

    // MARK: - Màn xem

    private func present(_ request: VideoWatchRequest, container: ModelContainer, retryCount: Int, completion: (() -> Void)?) {
        if let host = hostController, host.presentingViewController != nil, !host.isBeingDismissed {
            host.dismiss(animated: false) {
                MainActor.assumeIsolated {
                    VideoWatchPresenter.shared.present(request, container: container, retryCount: retryCount, completion: completion)
                }
            }
            return
        }
        guard let top = Self.readyTopViewController(retryCount: retryCount, retry: { next in
            VideoWatchPresenter.shared.present(request, container: container, retryCount: next, completion: completion)
        }, onGiveUp: { completion?() }) else { return }

        let model = VideoWatchModel(request: request, modelContainer: container)
        let host = VideoPlayerHostingController(rootView: AnyView(EmptyView()))
        host.modalPresentationStyle = .overFullScreen
        host.modalPresentationCapturesStatusBarAppearance = true
        host.view.backgroundColor = .black
        // Trình bày bằng UIKit ⇒ không thừa hưởng `.tint` / `.modelContainer` của `MainTabView`: gắn lại cả hai.
        let screen = VideoPlayerScreen(watch: model, onDismiss: { [weak host] in
            host?.dismiss(animated: true)
        })
        .appAccentTint()
        .modelContainer(container)
        host.rootView = AnyView(screen)
        hostController = host
        top.present(host, animated: true) {
            completion?()
        }
    }

    // MARK: - VC trên cùng

    /// VC trên cùng đang đứng yên; đang chuyển cảnh (màn xem vừa đóng…) ⇒ thử lại sau 0,3 giây, tối đa `maxRetryCount`
    /// lần rồi bỏ (log ❌). Trả `nil` khi đã hẹn thử lại / đã bỏ. Dùng chung với `VideoWatchPagePresenter`.
    static func readyTopViewController(
        retryCount: Int,
        retry: @escaping (Int) -> Void,
        onGiveUp: () -> Void
    ) -> UIViewController? {
        guard let top = VideoPlayerPresenter.findTopViewController() else {
            AppLogger.shared.log("❌ [VideoWatch] Không tìm được màn để trình bày màn xem phim / trang phụ")
            onGiveUp()
            return nil
        }
        guard top.isBeingPresented || top.isBeingDismissed else { return top }
        guard retryCount < maxRetryCount else {
            AppLogger.shared.log("❌ [VideoWatch] Trình bày thất bại: màn trên cùng đang chuyển cảnh quá lâu")
            onGiveUp()
            return nil
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            MainActor.assumeIsolated { retry(retryCount + 1) }
        }
        return nil
    }
}
