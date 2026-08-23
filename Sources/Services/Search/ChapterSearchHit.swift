import Foundation

/// Một kết quả tìm toàn văn: đủ danh tính để mở đúng chương **và** đúng đoạn trong Reader.
///
/// `paragraphIndex` là `ChapterTextLine.id` — chỉ số dòng thô **tính cả dòng trống**, thưa và
/// không phải array index. Nó khớp trực tiếp với `ParagraphItem.id` của Reader và
/// `ShelfReaderRoute.paragraphIndex`, nên không cần bất kỳ phép ánh xạ nào ở tầng View.
internal struct ChapterSearchHit: Identifiable, Sendable {
    internal let bookId: String
    internal let chapterIndex: Int
    internal let chapterUrl: String
    internal let chapterTitle: String
    internal let paragraphIndex: Int
    /// Đoạn xem trước quanh vị trí khớp, đã cắt và thêm dấu `…` nếu bị cắt.
    internal let snippet: String

    internal var id: String { "\(bookId)|\(chapterIndex)|\(paragraphIndex)" }
}
