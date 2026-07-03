import Foundation
import SwiftData

@Model
public final class Book {
    @Attribute(.unique) public var bookId: String // unique ID: sourceUrl + "_" + detailUrl
    public var title: String
    public var author: String
    public var coverUrl: String
    public var desc: String
    public var detailUrl: String
    public var sourceName: String
    public var sourceUrl: String
    public var extensionPackageId: String
    public var currentChapterIndex: Int = 0
    public var currentChapterPage: Int = 0 // số trang hiện tại hoặc vị trí cuộn
    public var lastReadDate: Date = Date()
    
    public var isOnShelf: Bool = true
    public var isHistory: Bool = false
    
    @Relationship(deleteRule: .cascade, inverse: \Chapter.book)
    public var chapters: [Chapter] = []
    
    public init(bookId: String, title: String, author: String, coverUrl: String, desc: String, detailUrl: String, sourceName: String, sourceUrl: String, extensionPackageId: String, currentChapterIndex: Int = 0, currentChapterPage: Int = 0, isOnShelf: Bool = true, isHistory: Bool = false) {
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
        self.isOnShelf = isOnShelf
        self.isHistory = isHistory
        self.lastReadDate = Date()
    }
}
