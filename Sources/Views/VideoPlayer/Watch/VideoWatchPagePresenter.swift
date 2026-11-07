import SwiftData
import SwiftUI
import UIKit

/// **Trang toàn màn của màn xem phim** (1.3.744) — thay cho sheet lớn cũ (`VideoWatchPresenter.presentPage`). Hai cách mở:
/// - **Đè lên màn xem** (`coversWatchScreen`): màn xem vẫn gắn bên dưới, phim vẫn phát. Dùng cho bấm một đề xuất **không
///   phải phim** (`openDetail` ⇒ `BookDetailView`), và cho thể loại / "Xem thêm ›" khi màn đang hiện bìa (phim khác chạy
///   nền) hoặc đang phát phim nhúng trang (`openCategory(_:model:)`). Phim không bao giờ mở trang Chi tiết kiểu cũ: bấm
///   phim là đổi phim tại chỗ, `⋮` của thẻ không còn "Mở trang chi tiết".
/// - **Sau khi màn xem đã đóng** (thể loại / Xem thêm lúc màn đang phát phim của nó): `VideoPlayerScreen` co phim vào cửa
///   sổ nhỏ, đóng màn rồi mới gọi `openCategory(_:packageId:sourceName:modelContainer:)`. Không còn `VideoWatchModel`.
///
/// ## Cách trình bày
/// - `UIHostingController` `.overFullScreen` lên VC trên cùng (cùng cách tìm với `VideoWatchPresenter`). **Không**
///   `.fullScreen`: kiểu đó gỡ màn xem khỏi cây view ⇒ `onDisappear` chạy ⇒ phim thu nhỏ vào hub. Ở đây màn xem vẫn gắn
///   bên dưới nên phim chạy tiếng như cũ, đóng trang là về đúng chỗ.
/// - `NavigationStack` riêng (trong trang vẫn đẩy tiếp được Chi tiết, thể loại khác…), nút `‹` đóng trang, màu nhấn +
///   `modelContainer` gắn lại ở gốc (trình bày bằng UIKit nên không thừa hưởng gì của `MainTabView`).
/// - Chỉ dọc: `VideoPlayerHostingController.supportedInterfaceOrientations` không áp cho trang này. Đang ngang thì xin
///   xoay dọc trước rồi mới mở.
///
/// ## Bấm phim trong trang
/// - Trang đè lên màn xem ⇒ đóng trang trước, **lượt sau** mới đổi phim tại chỗ (`VideoWatchModel.replace`) — mẫu
///   `BookActionSheet.emit`: đổi trong lúc trang đang đóng thì hai lượt chuyển cảnh chọi nhau.
/// - Trang mở sau khi màn đóng ⇒ đóng trang rồi mở màn xem mới theo lối thường (`VideoWatchPresenter.present`).
/// - Nguồn khác ⇒ `CategoryNovelsListView` đẩy Chi tiết ngay trong trang (hành vi mặc định).
///
/// ## Trang nằm **dưới** màn xem
/// Chạm cửa sổ nhỏ (hay dòng Video của hub) lúc trang mở sau khi màn đóng đang hiện ⇒ màn xem mở lại **trên** trang. Vì vậy:
/// - `isPresenting` (màn trình phát bị che ⇒ nút âm lượng cứng không hiện thanh, không bỏ tắt tiếng) và
///   `dismissCoveringPage` (màn xem đóng thì đóng trang đè lên nó trước) chỉ tính trang **đè lên** màn xem;
/// - mở trang mới: trang cũ đang trên cùng thì đóng nó trước; có màn khác phủ lên nó thì để nguyên — `dismiss` lên trang cũ
///   lúc đó sẽ đóng chính màn đang phủ lên nó;
/// - nút `‹` và lượt chọn phim đóng **đúng trang của mình** (`PageHandle`), không phải trang mở sau cùng.
@MainActor
final class VideoWatchPagePresenter {
    static let shared = VideoWatchPagePresenter()

    private weak var pageController: UIViewController?
    /// `pageController` được mở đè lên màn xem (màn vẫn gắn bên dưới).
    private var pageCoversWatchScreen = false

    private init() {}

    /// Có trang đang **đè lên màn xem** (không tính trang nằm dưới màn xem mở lại).
    static var isPresenting: Bool {
        guard shared.pageCoversWatchScreen, let page = shared.pageController else { return false }
        return page.presentingViewController != nil && !page.isBeingDismissed
    }

    // MARK: - Lối của màn xem

    /// Danh sách một thể loại / một nhóm đề xuất, **đè lên** màn xem (màn hiện bìa hoặc phim nhúng trang). Chọn phim ⇒
    /// đóng trang rồi đổi phim tại chỗ.
    static func openCategory(_ category: CategoryResult, model: VideoWatchModel) {
        let packageId = model.request.packageId
        let sourceName = model.request.sourceName
        AppLogger.shared.log("🎬 [VideoWatch] Mở trang '\(category.title)' đè lên màn xem, phim vẫn phát")
        present(modelContainer: model.modelContainer, coversWatchScreen: true) { page in
            categoryList(category, packageId: packageId, sourceName: sourceName) { [weak model] request in
                AppLogger.shared.log("🎬 [VideoWatch] Chọn phim trong trang ⇒ đóng trang, đổi phim tại chỗ")
                page.close { model?.replace(with: request) }
            }
        }
    }

    /// Danh sách một thể loại / một nhóm đề xuất, mở **sau khi** màn xem đã đóng (phim ở cửa sổ nhỏ). Chọn phim ⇒ đóng
    /// trang rồi mở màn xem mới theo lối thường.
    static func openCategory(
        _ category: CategoryResult,
        packageId: String,
        sourceName: String,
        modelContainer: ModelContainer
    ) {
        AppLogger.shared.log("🎬 [VideoWatch] Mở trang '\(category.title)' sau khi màn xem đóng (phim ở cửa sổ nhỏ)")
        present(modelContainer: modelContainer, coversWatchScreen: false) { page in
            categoryList(category, packageId: packageId, sourceName: sourceName) { request in
                AppLogger.shared.log("🎬 [VideoWatch] Chọn phim trong trang ⇒ đóng trang, mở màn xem mới")
                page.close { VideoWatchPresenter.present(request, modelContainer: modelContainer) }
            }
        }
    }

    /// Trang Chi tiết của một đề xuất không phải phim.
    static func openDetail(_ request: VideoWatchRequest, modelContainer: ModelContainer) {
        AppLogger.shared.log("🎬 [VideoWatch] Mở trang Chi tiết đè lên màn xem, phim vẫn phát")
        present(modelContainer: modelContainer, coversWatchScreen: true) { _ in
            BookDetailView(
                bookId: request.detailUrl,
                extensionPackageId: request.packageId,
                initialDetailUrl: request.detailUrl,
                sourceName: request.sourceName,
                initialHost: request.host
            )
        }
    }

    private static func categoryList(
        _ category: CategoryResult,
        packageId: String,
        sourceName: String,
        onSelectVideo: @escaping (VideoWatchRequest) -> Void
    ) -> CategoryNovelsListView {
        let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId)
        return CategoryNovelsListView(
            category: category,
            extensionPackageId: packageId,
            localPath: ext?.localPath ?? "",
            downloadUrl: ext?.downloadUrl ?? "",
            configJson: ext?.configJson ?? "{}",
            sourceName: sourceName,
            onSelectVideo: { item in
                onSelectVideo(VideoWatchRequest(
                    packageId: packageId,
                    detailUrl: item.link,
                    sourceName: sourceName,
                    host: item.host,
                    title: item.name,
                    coverUrl: item.cover
                ))
            }
        )
    }

    // MARK: - Trình bày / đóng

    private static func present<Content: View>(
        modelContainer: ModelContainer,
        coversWatchScreen: Bool,
        @ViewBuilder content: (PageHandle) -> Content
    ) {
        let handle = PageHandle()
        let root = AnyView(
            PageRoot(content: content(handle), handle: handle, coversWatchScreen: coversWatchScreen)
                .appAccentTint()
                .modelContainer(modelContainer)
        )
        guard VideoOrientationLock.isInterfaceLandscape else {
            shared.present(root, handle: handle, coversWatchScreen: coversWatchScreen, retryCount: 0)
            return
        }
        VideoOrientationLock.rotate(toLandscape: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated {
                VideoWatchPagePresenter.shared.present(root, handle: handle, coversWatchScreen: coversWatchScreen, retryCount: 0)
            }
        }
    }

    /// Màn xem sắp đóng: đóng trang **đè lên** nó (nếu có) rồi gọi `completion` ở nhịp main kế tiếp; không có ⇒ gọi ngay.
    /// Đóng từ màn bên dưới trang ⇒ sheet đang mở trên trang (nếu có) đóng theo. Trang nằm dưới màn xem không bị đụng tới.
    static func dismissCoveringPage(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard shared.pageCoversWatchScreen, let page = shared.pageController,
              let presenter = page.presentingViewController, !page.isBeingDismissed else {
            completion?()
            return
        }
        presenter.dismiss(animated: animated) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion?() }
            }
        }
    }

    private func present(_ root: AnyView, handle: PageHandle, coversWatchScreen: Bool, retryCount: Int) {
        if let page = pageController, page.presentingViewController != nil, !page.isBeingDismissed,
           page.presentedViewController == nil {
            page.dismiss(animated: false) {
                MainActor.assumeIsolated {
                    VideoWatchPagePresenter.shared.present(
                        root, handle: handle, coversWatchScreen: coversWatchScreen, retryCount: retryCount
                    )
                }
            }
            return
        }
        guard let top = VideoWatchPresenter.readyTopViewController(retryCount: retryCount, retry: { next in
            VideoWatchPagePresenter.shared.present(root, handle: handle, coversWatchScreen: coversWatchScreen, retryCount: next)
        }, onGiveUp: {}) else { return }

        let page = PortraitHostingController(rootView: root)
        page.modalPresentationStyle = .overFullScreen
        page.modalPresentationCapturesStatusBarAppearance = true
        handle.controller = page
        pageController = page
        pageCoversWatchScreen = coversWatchScreen
        top.present(page, animated: true)
    }

    // MARK: - Kiểu con

    /// Tham chiếu yếu tới VC của **chính trang** — nút `‹` và lượt chọn phim đóng đúng trang của mình (trang mở sau có thể
    /// đã thay `pageController`).
    @MainActor
    fileprivate final class PageHandle {
        weak var controller: UIViewController?

        /// Đóng trang rồi gọi `completion` ở nhịp main kế tiếp; trang không còn hiện ⇒ gọi ngay.
        func close(animated: Bool = true, completion: (() -> Void)? = nil) {
            guard let page = controller, page.presentingViewController != nil, !page.isBeingDismissed else {
                completion?()
                return
            }
            page.dismiss(animated: animated) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { completion?() }
                }
            }
        }
    }

    /// Trang chỉ dọc (UIKit hỏi VC được trình bày `.overFullScreen` trên cùng).
    private final class PortraitHostingController: UIHostingController<AnyView> {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    }

    /// `NavigationStack` riêng + nút `‹` đóng trang (gốc stack không có nút back của hệ thống).
    private struct PageRoot<Content: View>: View {
        let content: Content
        let handle: PageHandle
        let coversWatchScreen: Bool

        var body: some View {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                handle.close()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 38, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(coversWatchScreen ? "Quay lại màn xem phim" : "Quay lại")
                        }
                    }
            }
        }
    }
}
