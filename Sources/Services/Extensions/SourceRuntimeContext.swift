import Foundation

/// Ngữ cảnh truyện/chương tuỳ chọn cho `SourceRuntime`.
///
/// Nguồn Legado dùng nó cho kho biến theo truyện/chương và đối tượng `book`/`chapter` mà JS của nguồn đọc
/// (`book.name`, `chapter.title`, `chapter.index`…); tiện ích JS bỏ qua hoàn toàn.
///
/// - `bookId`: id sách **thật** của app (`Book.bookId`) khi có — trạng thái bền của nguồn Legado gắn theo id này.
/// - `bookUrl`: URL trang chi tiết (`Book.detailUrl` / `link` của item tìm kiếm), nguyên văn.
public struct SourceRuntimeContext: Sendable {
    public let bookId: String?
    public let bookUrl: String?
    public let bookName: String?
    public let bookAuthor: String?
    public let chapterTitle: String?
    public let chapterIndex: Int?

    public init(
        bookId: String? = nil,
        bookUrl: String? = nil,
        bookName: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        chapterIndex: Int? = nil
    ) {
        self.bookId = bookId
        self.bookUrl = bookUrl
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.chapterIndex = chapterIndex
    }
}
