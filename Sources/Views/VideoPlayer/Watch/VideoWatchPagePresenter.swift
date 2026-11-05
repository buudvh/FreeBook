import SwiftData
import SwiftUI
import UIKit

/// **Trang toàn màn đè lên màn xem phim** (1.3.744) — thay cho sheet lớn cũ (`VideoWatchPresenter.presentPage`, mở sau
/// khi đã thu nhỏ phim). Ba lối dùng chung:
/// - thể loại (nhãn `#` trên tên + chip của sheet Thông tin) và "Xem thêm ›" của một nhóm đề xuất ⇒ `openCategory`
///   (`CategoryNovelsListView`);
/// - "Mở trang chi tiết" ở `⋮` của thẻ đề xuất (và đề xuất không phải phim) ⇒ `openDetail` (`BookDetailView`).
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
/// Nguồn video ⇒ đóng trang trước, **lượt sau** mới đổi phim tại chỗ (`VideoWatchModel.replace`) — mẫu
/// `BookActionSheet.emit`: đổi trong lúc trang đang đóng thì hai lượt chuyển cảnh chọi nhau. Nguồn khác ⇒
/// `CategoryNovelsListView` đẩy Chi tiết ngay trong trang (hành vi mặc định).
///
/// `isPresenting`: màn trình phát bị trang che ⇒ nút âm lượng cứng không hiện thanh, không bỏ tắt tiếng phim
/// (`VideoPlayerScreen`).
@MainActor
final class VideoWatchPagePresenter {
    static let shared = VideoWatchPagePresenter()

    private weak var pageController: UIViewController?

    private init() {}

    static var isPresenting: Bool {
        guard let page = shared.pageController else { return false }
        return page.presentingViewController != nil && !page.isBeingDismissed
    }

    // MARK: - Ba lối của màn xem

    /// Danh sách một thể loại / một nhóm đề xuất của tiện ích đang xem.
    static func openCategory(_ category: CategoryResult, model: VideoWatchModel) {
        let packageId = model.request.packageId
        let sourceName = model.request.sourceName
        let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: packageId)
        AppLogger.shared.log("🎬 [VideoWatch] Mở trang '\(category.title)' đè lên màn xem, phim vẫn phát")
        present(modelContainer: model.modelContainer) {
            CategoryNovelsListView(
                category: category,
                extensionPackageId: packageId,
                localPath: ext?.localPath ?? "",
                downloadUrl: ext?.downloadUrl ?? "",
                configJson: ext?.configJson ?? "{}",
                sourceName: sourceName,
                onSelectVideo: { [weak model] item in
                    let request = VideoWatchRequest(
                        packageId: packageId,
                        detailUrl: item.link,
                        sourceName: sourceName,
                        host: item.host,
                        title: item.name,
                        coverUrl: item.cover
                    )
                    AppLogger.shared.log("🎬 [VideoWatch] Chọn phim trong trang ⇒ đóng trang, đổi phim tại chỗ")
                    VideoWatchPagePresenter.dismiss { model?.replace(with: request) }
                }
            )
        }
    }

    /// Trang Chi tiết của một đề xuất.
    static func openDetail(_ request: VideoWatchRequest, modelContainer: ModelContainer) {
        AppLogger.shared.log("🎬 [VideoWatch] Mở trang Chi tiết đè lên màn xem, phim vẫn phát")
        present(modelContainer: modelContainer) {
            BookDetailView(
                bookId: request.detailUrl,
                extensionPackageId: request.packageId,
                initialDetailUrl: request.detailUrl,
                sourceName: request.sourceName,
                initialHost: request.host
            )
        }
    }

    // MARK: - Trình bày / đóng

    static func present<Content: View>(modelContainer: ModelContainer, @ViewBuilder content: () -> Content) {
        let root = AnyView(
            PageRoot(content: content())
                .appAccentTint()
                .modelContainer(modelContainer)
        )
        guard VideoOrientationLock.isInterfaceLandscape else {
            shared.present(root, retryCount: 0)
            return
        }
        VideoOrientationLock.rotate(toLandscape: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            MainActor.assumeIsolated { VideoWatchPagePresenter.shared.present(root, retryCount: 0) }
        }
    }

    /// Đóng trang (nếu có) rồi gọi `completion` ở nhịp main kế tiếp; không có trang ⇒ gọi ngay.
    static func dismiss(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard let page = shared.pageController, page.presentingViewController != nil, !page.isBeingDismissed else {
            completion?()
            return
        }
        page.dismiss(animated: animated) {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion?() }
            }
        }
    }

    private func present(_ root: AnyView, retryCount: Int) {
        if let page = pageController, page.presentingViewController != nil, !page.isBeingDismissed {
            page.dismiss(animated: false) {
                MainActor.assumeIsolated {
                    VideoWatchPagePresenter.shared.present(root, retryCount: retryCount)
                }
            }
            return
        }
        guard let top = VideoWatchPresenter.readyTopViewController(retryCount: retryCount, retry: { next in
            VideoWatchPagePresenter.shared.present(root, retryCount: next)
        }, onGiveUp: {}) else { return }

        let page = PortraitHostingController(rootView: root)
        page.modalPresentationStyle = .overFullScreen
        page.modalPresentationCapturesStatusBarAppearance = true
        pageController = page
        top.present(page, animated: true)
    }

    // MARK: - Kiểu con

    /// Trang chỉ dọc (UIKit hỏi VC được trình bày `.overFullScreen` trên cùng).
    private final class PortraitHostingController: UIHostingController<AnyView> {
        override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    }

    /// `NavigationStack` riêng + nút `‹` đóng trang (gốc stack không có nút back của hệ thống).
    private struct PageRoot<Content: View>: View {
        let content: Content

        var body: some View {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button {
                                VideoWatchPagePresenter.dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 17, weight: .semibold))
                                    .frame(width: 38, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Quay lại màn xem phim")
                        }
                    }
            }
        }
    }
}
