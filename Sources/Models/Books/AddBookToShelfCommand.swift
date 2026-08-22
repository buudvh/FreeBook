import Foundation

public struct AddBookToShelfCommand: Sendable {
    public let bookId: String
    public let title: String
    public let author: String
    public let coverUrl: String
    public let desc: String
    public let detailUrl: String
    public let sourceName: String
    public let sourceUrl: String
    public let extensionPackageId: String
    public let currentChapterIndex: Int
    public let currentChapterPage: Int
    public let currentChapterTitle: String
    public let isOnShelf: Bool
    public let isHistory: Bool
    public let host: String?
    /// Mốc đọc gần nhất muốn giữ lại (dùng khi khôi phục sao lưu để kệ sách giữ đúng thứ tự cũ).
    /// `nil` = lấy thời điểm hiện tại, giữ nguyên hành vi thêm sách thủ công.
    public let lastReadDate: Date?

    public init(
        bookId: String,
        title: String,
        author: String,
        coverUrl: String,
        desc: String,
        detailUrl: String,
        sourceName: String,
        sourceUrl: String,
        extensionPackageId: String,
        currentChapterIndex: Int = 0,
        currentChapterPage: Int = 0,
        currentChapterTitle: String = "",
        isOnShelf: Bool = true,
        isHistory: Bool = false,
        host: String? = nil,
        lastReadDate: Date? = nil
    ) {
        self.bookId = bookId
        self.title = title
        self.author = author
        self.coverUrl = coverUrl
        self.desc = desc
        self.detailUrl = detailUrl
        self.sourceName = sourceName
        self.sourceUrl = sourceUrl
        self.extensionPackageId = extensionPackageId
        self.currentChapterIndex = currentChapterIndex
        self.currentChapterPage = currentChapterPage
        self.currentChapterTitle = currentChapterTitle
        self.isOnShelf = isOnShelf
        self.isHistory = isHistory
        self.host = host
        self.lastReadDate = lastReadDate
    }
}
