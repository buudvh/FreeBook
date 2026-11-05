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
/// - `presentPage`: trang phụ mở **sau khi** màn xem đã đóng (danh sách thể loại, Chi tiết của một đề xuất) — sheet lớn
///   có `NavigationStack` riêng, vuốt xuống để đóng. Một trang phụ một lúc.
@MainActor
final class VideoWatchPresenter {
    static let shared = VideoWatchPresenter()

    private weak var hostController: UIViewController?
    private weak var pageController: UIViewController?
    private static let maxRetryCount = 6

    private init() {}

    static func present(_ request: VideoWatchRequest, modelContainer: ModelContainer, completion: (() -> Void)? = nil) {
        shared.present(request, container: modelContainer, retryCount: 0, completion: completion)
    }

    /// Trang phụ của màn xem. `content` được bọc `NavigationStack` + màu nhấn + `modelContainer` (trình bày bằng UIKit
    /// nên không thừa hưởng gì của `MainTabView`).
    static func presentPage<Content: View>(modelContainer: ModelContainer, @ViewBuilder content: () -> Content) {
        let page = content()
        let root = NavigationStack { page }
            .appAccentTint()
            .modelContainer(modelContainer)
        shared.presentPage(AnyView(root), retryCount: 0)
    }

    /// Đóng trang phụ đang mở (nếu có) rồi gọi `completion` — nút Home của màn xem dọn hết lớp phủ của nó trước khi
    /// chuyển tab.
    static func dismissPage(completion: @escaping () -> Void) {
        guard let page = shared.pageController, page.presentingViewController != nil, !page.isBeingDismissed else {
            completion()
            return
        }
        page.dismiss(animated: true) {
            MainActor.assumeIsolated { completion() }
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

    // MARK: - Trang phụ

    private func presentPage(_ root: AnyView, retryCount: Int) {
        if let page = pageController, page.presentingViewController != nil, !page.isBeingDismissed {
            page.dismiss(animated: false) {
                MainActor.assumeIsolated {
                    VideoWatchPresenter.shared.presentPage(root, retryCount: retryCount)
                }
            }
            return
        }
        guard let top = Self.readyTopViewController(retryCount: retryCount, retry: { next in
            VideoWatchPresenter.shared.presentPage(root, retryCount: next)
        }, onGiveUp: {}) else { return }

        let page = UIHostingController(rootView: root)
        page.modalPresentationStyle = .pageSheet
        if let sheet = page.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        pageController = page
        top.present(page, animated: true)
    }

    // MARK: - VC trên cùng

    /// VC trên cùng đang đứng yên; đang chuyển cảnh (màn xem vừa đóng…) ⇒ thử lại sau 0,3 giây, tối đa `maxRetryCount`
    /// lần rồi bỏ (log ❌). Trả `nil` khi đã hẹn thử lại / đã bỏ.
    private static func readyTopViewController(
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
