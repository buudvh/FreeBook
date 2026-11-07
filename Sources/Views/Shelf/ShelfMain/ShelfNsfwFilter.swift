import Foundation

/// Bộ lọc NSFW **riêng** của danh sách Kệ + Lịch sử ở tab Kệ Sách (1.3.778) — độc lập với công tắc NSFW chung
/// (`RepositoryFilterPolicy.includeNsfwDefaultsKey`, vẫn quyết định Khám phá / Bộ sưu tập / Tải / Tìm trên kệ). Trạng thái
/// sống trong `ShelfNsfwFilterState` (không lưu đĩa). "NSFW" = truyện của nguồn NSFW hoặc truyện người dùng tự đánh dấu
/// (`NsfwBookMarkStore`), cùng luật `ShelfBookPartition`.
enum ShelfNsfwFilter: CaseIterable {
    /// Mặc định — mở app, rời app, bấm Home đều quay về đây.
    case hide
    case all
    case only

    var title: String {
        switch self {
        case .hide: return "Không hiển thị NSFW"
        case .all: return "Tất cả"
        case .only: return "Chỉ NSFW"
        }
    }

    /// Có giữ một truyện (đã biết là NSFW hay không) trong danh sách không.
    func keeps(isNsfw: Bool) -> Bool {
        switch self {
        case .hide: return !isNsfw
        case .all: return true
        case .only: return isNsfw
        }
    }
}
