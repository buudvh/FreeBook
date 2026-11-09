import SwiftData
import SwiftUI

/// Đủ để gắn ⋮ "Thêm vào playlist / Thêm vào kệ" (`PlaylistListItemMenu`) lên item của **một danh sách** chưa mở —
/// Khám phá (Trang chủ, tab danh mục), Thể loại / Xem thêm, Tìm một nguồn / nhiều nguồn (1.3.810).
///
/// Dựng **một lần mỗi danh sách** (Tìm nhiều nguồn: mỗi nguồn một lần) bằng `make`: loại suy lúc chạy
/// (`ExtensionContentKind.resolve(packageId:)`), chỉ âm thanh / phim mới có playlist ⇒ truyện chữ / truyện tranh trả
/// `nil` (không có ⋮). `ModelContainer` truyền tường minh: màn nghe / màn xem trình bày bằng UIKit không chắc có
/// `modelContext` trong environment.
struct PlaylistListAddContext {
    let packageId: String
    let sourceName: String
    let kind: PlaylistKind
    let modelContainer: ModelContainer

    /// `sourceName` rỗng / `nil` ⇒ tên tiện ích đã cài.
    @MainActor
    static func make(packageId: String?, sourceName: String? = nil, modelContainer: ModelContainer) -> PlaylistListAddContext? {
        guard let packageId, !packageId.isEmpty,
              let kind = PlaylistKind(contentKind: ExtensionContentKind.resolve(packageId: packageId)) else {
            return nil
        }
        let name = ExtensionHostResolver.nonEmpty(sourceName)
            ?? ExtensionLibraryRepository.snapshot(packageId: packageId)?.name
            ?? ""
        return PlaylistListAddContext(packageId: packageId, sourceName: name, kind: kind, modelContainer: modelContainer)
    }

    /// Album / phim của item (id = id trình nghe / màn xem sẽ dùng — `PlaylistItemMapper.album(of:…)`).
    @MainActor
    func album(of item: ExtensionItemResult, detailUrl: String? = nil) -> PlaylistAlbumInfo {
        PlaylistItemMapper.album(
            of: item,
            detailUrl: detailUrl,
            packageId: packageId,
            sourceName: sourceName,
            in: modelContainer.mainContext
        )
    }

    /// Đầu vào của "Thêm vào kệ" (`VideoWatchShelfAdder` — dùng được cho cả album âm thanh, cùng cách tạo `Book`).
    func shelfRequest(for item: ExtensionItemResult, detailUrl: String? = nil) -> VideoWatchRequest {
        VideoWatchRequest(
            packageId: packageId,
            detailUrl: detailUrl ?? item.link,
            sourceName: sourceName,
            host: item.host,
            title: item.name,
            coverUrl: item.cover
        )
    }
}
