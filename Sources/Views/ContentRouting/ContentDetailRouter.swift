import SwiftData
import SwiftUI

/// Lối mở **một item danh sách** (Khám phá, Tìm, Thể loại, Đề xuất, nhập từ trình duyệt…): nội dung video ⇒ màn xem
/// phim (`VideoWatchPresenter`, phát dọc ngay); loại khác ⇒ trả `false` để chỗ gọi đẩy `BookDetailView` như cũ.
///
/// Loại suy từ tiện ích lúc bấm (`ExtensionContentKind.resolve(packageId:)`, đồng bộ, rẻ). Id phim **không** lấy từ chỗ gọi
/// (mỗi màn danh sách tự chế một kiểu: link, `tên_link`…) mà do `VideoWatchRequest.resolveBookId` phân giải.
/// Chỗ đang là `NavigationLink` thì dùng `ContentDetailLink` (nút khi là video, link khi không).
@MainActor
enum ContentDetailRouter {
    static func isVideo(packageId: String) -> Bool {
        ExtensionContentKind.resolve(packageId: packageId) == .video
    }

    /// Video ⇒ mở màn xem và trả `true`; loại khác ⇒ `false`, không làm gì.
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
        guard isVideo(packageId: packageId) else { return false }
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
