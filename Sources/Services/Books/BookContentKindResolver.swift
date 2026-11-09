import Foundation

/// Loại nội dung của **một cuốn sách đã lưu** — đúng luật router `BookContentDestination` dùng để chọn màn mở, để các
/// danh sách lọc theo loại (vd sheet chọn truyện nguồn / đích của từ điển) không lệch với màn thật sự mở ra.
///
/// Thứ tự: ghi đè loại **của sách** ở nguồn Legado (`LegadoBookTypeOverride`, spec §13.6) → loại của tiện ích (bản cài →
/// catalog, `ExtensionContentKind.resolveIfKnown`) → tiện ích đã gỡ và không còn trong catalog: có chương truyện tranh /
/// tập phim tải offline thì là tranh / phim, còn lại coi là chữ. Gọi được từ thread bất kỳ (các nguồn đều có lock / chỉ
/// đọc đĩa).
enum BookContentKindResolver {
    static func kind(bookId: String, packageId: String) -> ExtensionContentKind {
        if let override = LegadoBookTypeOverride.shared.contentKind(bookId: bookId, packageId: packageId) { return override }
        if let known = ExtensionContentKind.resolveIfKnown(packageId: packageId) { return known }
        if !ComicOfflineStore.downloadedChapterIndexes(bookId: bookId).isEmpty { return .comic }
        return VideoOfflineStore.downloadedEpisodeIndexes(bookId: bookId).isEmpty ? .text : .video
    }

    /// Sách mở bằng Reader chữ (`.text`; `.unsupported` cũng rơi vào Reader chữ ở router).
    static func isTextBook(bookId: String, packageId: String) -> Bool {
        switch kind(bookId: bookId, packageId: packageId) {
        case .text, .unsupported: return true
        case .comic, .video, .audio: return false
        }
    }
}
