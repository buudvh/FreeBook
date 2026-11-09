import SwiftData
import SwiftUI

/// Lối mở **một item danh sách** (Khám phá, Tìm, Thể loại, Đề xuất, nhập từ trình duyệt…): nội dung video ⇒ màn xem
/// phim (`VideoWatchPresenter`, phát dọc ngay); nội dung âm thanh ⇒ màn nghe (`AudioPlayerPresenter`, phát ngay); loại
/// khác ⇒ trả `false` để chỗ gọi đẩy `BookDetailView` như cũ. Phim và album âm thanh không bao giờ mở trang Chi tiết.
///
/// Loại suy từ tiện ích lúc bấm (`ExtensionContentKind.resolve(packageId:)`, đồng bộ, rẻ). Id phim / album **không** lấy
/// từ chỗ gọi (mỗi màn danh sách tự chế một kiểu: link, `tên_link`…) mà do `VideoWatchRequest.resolveBookId` /
/// `AudioListenRequest.resolveBookId` phân giải.
/// Chỗ đang là `NavigationLink` thì dùng `ContentDetailLink` (nút khi mở thẳng màn phát, link khi không).
@MainActor
enum ContentDetailRouter {
    /// Chỉ phim — lối đổi phim tại chỗ của trang thể loại trên màn xem (`CategoryNovelsListView.onSelectVideo`).
    static func isVideo(packageId: String) -> Bool {
        ExtensionContentKind.resolve(packageId: packageId) == .video
    }

    /// Phim hoặc âm thanh: item mở thẳng màn phát (`openIfVideo` trả `true`), không có trang Chi tiết.
    static func opensPlayer(packageId: String) -> Bool {
        ExtensionContentKind.resolve(packageId: packageId).isPlayable
    }

    /// Video ⇒ mở màn xem, âm thanh ⇒ mở màn nghe, rồi trả `true`; loại khác ⇒ `false`, không làm gì. Tên giữ từ thời chỉ
    /// có phim (mọi lối mở item danh sách đã gọi hàm này nên tự nhận thêm âm thanh).
    @discardableResult
    static func openIfVideo(
        packageId: String,
        detailUrl: String,
        sourceName: String,
        host: String?,
        title: String? = nil,
        coverUrl: String? = nil,
        modelContainer: ModelContainer
    ) -> Bool {
        switch ExtensionContentKind.resolve(packageId: packageId) {
        case .video:
            AppLogger.shared.log("🎬 [VideoWatch] Mở phim từ danh sách ⇒ màn xem (tiện ích=\(packageId))")
            VideoWatchPresenter.present(
                VideoWatchRequest(
                    packageId: packageId,
                    detailUrl: detailUrl,
                    sourceName: sourceName,
                    host: host,
                    title: title,
                    coverUrl: coverUrl
                ),
                modelContainer: modelContainer
            )
            return true
        case .audio:
            AppLogger.shared.log("🎵 [AudioPlayerUI] Mở album từ danh sách ⇒ màn nghe (tiện ích=\(packageId))")
            AudioPlayerPresenter.present(
                AudioListenRequest(
                    packageId: packageId,
                    detailUrl: detailUrl,
                    sourceName: sourceName,
                    host: host,
                    title: title,
                    coverUrl: coverUrl
                ),
                modelContainer: modelContainer
            )
            return true
        case .text, .comic, .unsupported:
            return false
        }
    }

    /// Bản cho item kết quả của script (`ExtensionItemResult`): tên / bìa của item hiện ngay trong lúc tải chi tiết.
    @discardableResult
    static func openIfVideo(
        _ item: ExtensionItemResult,
        packageId: String,
        sourceName: String,
        modelContainer: ModelContainer
    ) -> Bool {
        openIfVideo(
            packageId: packageId,
            detailUrl: item.link,
            sourceName: sourceName,
            host: item.host,
            title: item.name,
            coverUrl: item.cover,
            modelContainer: modelContainer
        )
    }
}
