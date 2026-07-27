import Foundation

internal struct StoredChapterSnapshot: Sendable, Equatable {
    internal let id: String
    internal let bookId: String
    internal let title: String
    internal let url: String
    internal let index: Int
    internal let host: String?
    internal let titleTrans: String?
    internal let isCached: Bool
    internal let offset: Int64
    internal let length: Int64
    internal let updatedAt: Date

    internal init(
        id: String,
        bookId: String,
        title: String,
        url: String,
        index: Int,
        host: String? = nil,
        titleTrans: String? = nil,
        isCached: Bool = false,
        offset: Int64 = 0,
        length: Int64 = 0,
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.title = title
        self.url = url
        self.index = index
        self.host = host
        self.titleTrans = titleTrans
        self.isCached = isCached
        self.offset = offset
        self.length = length
        self.updatedAt = updatedAt
    }
}
