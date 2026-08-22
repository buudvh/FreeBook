import Foundation

/// Payload bất biến cho việc người dùng tự sửa thông tin truyện ở màn Chi Tiết Truyện.
///
/// Khác `updateBookMetadata` (dùng cho dữ liệu bóc tách lại từ extension), command này **buộc**
/// coordinator tính lại `titleTrans`/`authorTrans`: kệ sách hiển thị hai field dịch đó, nên đổi tên
/// mà không tính lại sẽ thấy tên dịch cũ.
public struct EditBookInfoCommand: Sendable, Equatable {
    public let bookId: String
    public let title: String
    public let author: String
    public let coverUrl: String

    public init(bookId: String, title: String, author: String, coverUrl: String) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
    }
}
