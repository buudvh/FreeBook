import SwiftData
import SwiftUI
import UIKit

/// Mở **màn xem phim** (`VideoPlayerScreen(watch:onDismiss:)`) từ mọi lối vào phim (Khám phá, Tìm, Thể loại, Đề xuất…).
///
/// Trình bày bằng UIKit `.overFullScreen` như `VideoPlayerPresenter` (cùng `VideoPlayerHostingController`, cùng cách tìm
/// VC trên cùng): màn bên dưới vẫn sống, và trình phát **không** nằm trong `NavigationStack` — đẩy một màn khác lên
/// stack (đề xuất, thể loại, đổi nguồn, đổi tab) sẽ làm màn trình phát "biến mất" ⇒ tự thu nhỏ.
///
/// Cách dùng: `VideoWatchPresenter.present(VideoWatchRequest(...), modelContainer: modelContext.container)`. Màn xem đang
/// mở thì đóng nó trước rồi mới mở màn mới (không chồng hai màn xem).
@MainActor
final class VideoWatchPresenter {
    static let shared = VideoWatchPresenter()

    private weak var hostController: UIViewController?
    private static let maxRetryCount = 6

    private init() {}

    static func present(_ request: VideoWatchRequest, modelContainer: ModelContainer) {
        shared.present(request, container: modelContainer, retryCount: 0)
    }

    private func present(_ request: VideoWatchRequest, container: ModelContainer, retryCount: Int) {
        if let host = hostController, host.presentingViewController != nil, !host.isBeingDismissed {
            host.dismiss(animated: false) {
                MainActor.assumeIsolated {
                    VideoWatchPresenter.shared.present(request, container: container, retryCount: retryCount)
                }
            }
            return
        }
        guard let top = VideoPlayerPresenter.findTopViewController() else {
            AppLogger.shared.log("❌ [VideoWatch] Không tìm được màn để mở màn xem phim")
            return
        }
        if top.isBeingPresented || top.isBeingDismissed {
            guard retryCount < Self.maxRetryCount else {
                AppLogger.shared.log("❌ [VideoWatch] Mở màn xem phim thất bại: màn trên cùng đang chuyển cảnh quá lâu")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated {
                    VideoWatchPresenter.shared.present(request, container: container, retryCount: retryCount + 1)
                }
            }
            return
        }

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
        top.present(host, animated: true)
    }
}
