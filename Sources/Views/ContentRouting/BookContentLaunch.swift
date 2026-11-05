import Foundation

/// Bộ tham số mở nội dung một cuốn sách — đúng các tham số của `ReaderView(...)`, để `BookContentDestination`
/// chuyển nguyên vẹn sang `ReaderView`, `ComicReaderView` hoặc `VideoPlayerScreen`.
///
/// `initialParagraphIndex` là `Int?` như `ReaderView`: `nil` = dùng tiến độ đã lưu, `-1` = đầu chương.
/// Với truyện tranh trường này là chỉ số ảnh, với video là **số giây** (bất biến 6 của plan comic/video).
///
/// Không khai `Sendable`: `ChapterResult` là struct `public` chưa khai `Sendable`. Type này chỉ sống trên MainActor.
struct BookContentLaunch: Equatable {
    let bookId: String
    let extensionPackageId: String
    let chapterIndex: Int
    let onlineChapters: [ChapterResult]
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDesc: String?
    let bookDetailUrl: String?
    let bookSourceName: String?
    let initialParagraphIndex: Int?
    /// Host của sách (item / chi tiết) khi chưa có `Book` để đọc `Book.host` — trình phát dùng sau `Book.host`. Khai `var`
    /// có mặc định và đứng cuối để init memberwise của mọi chỗ khởi tạo cũ không đổi.
    var host: String? = nil
}
