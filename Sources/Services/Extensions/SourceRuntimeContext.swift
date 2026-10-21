import Foundation

/// Ngữ cảnh truyện/chương tuỳ chọn cho `SourceRuntime`.
///
/// Nguồn Legado dùng nó cho kho biến theo truyện/chương và đối tượng `book`/`chapter` mà JS của nguồn đọc
/// (`book.name`, `chapter.title`, `chapter.index`…); tiện ích JS bỏ qua hoàn toàn.
///
/// - `bookId`: id sách **thật** của app (`Book.bookId`) khi có — trạng thái bền của nguồn Legado gắn theo id này.
/// - `bookUrl`: URL trang chi tiết (`Book.detailUrl` / `link` của item tìm kiếm), nguyên văn.
/// - `isInteractive`: lời gọi do người dùng bấm và đang nhìn kết quả (mở trang sách, đọc chương đang mở, trang ảnh
///   của chương tranh đang mở…). Chỉ khi `true` engine Legado mới được mở trình duyệt / hỏi mã xác minh / hiện toast
///   (spec §10.8); tải nền, tải trước, kiểm tra hàng loạt, "tìm mọi nguồn" giữ mặc định `false`.
public struct SourceRuntimeContext: Sendable {
    public let bookId: String?
    public let bookUrl: String?
    public let bookName: String?
    public let bookAuthor: String?
    public let chapterTitle: String?
    public let chapterIndex: Int?
    public let isInteractive: Bool

    public init(
        bookId: String? = nil,
        bookUrl: String? = nil,
        bookName: String? = nil,
        bookAuthor: String? = nil,
        chapterTitle: String? = nil,
        chapterIndex: Int? = nil,
        isInteractive: Bool = false
    ) {
        self.bookId = bookId
        self.bookUrl = bookUrl
        self.bookName = bookName
        self.bookAuthor = bookAuthor
        self.chapterTitle = chapterTitle
        self.chapterIndex = chapterIndex
        self.isInteractive = isInteractive
    }
}
