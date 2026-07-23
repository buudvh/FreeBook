import Foundation

public struct ChapterModel: Identifiable, Sendable, Codable, Equatable {
    public var id: String
    public var bookId: String
    public var index: Int
    public var title: String
    public var url: String
    public var isCached: Bool
    public var offset: Int64
    public var length: Int64
    public var host: String?
    public var titleTrans: String?

    public init(
        id: String? = nil,
        bookId: String,
        index: Int,
        title: String,
        url: String,
        isCached: Bool = false,
        offset: Int64 = 0,
        length: Int64 = 0,
        host: String? = nil,
        titleTrans: String? = nil
    ) {
        self.bookId = bookId
        self.index = index
        self.title = title
        self.url = url
        self.isCached = isCached
        self.offset = offset
        self.length = length
        self.host = host
        self.titleTrans = titleTrans
        self.id = id ?? ChapterModel.generateId(bookId: bookId, url: url, index: index)
    }

    public static func generateId(bookId: String, url: String, index: Int = 0) -> String {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedUrl.isEmpty {
            return "\(bookId)|I:\(index)"
        } else {
            return "\(bookId)|U:\(trimmedUrl)"
        }
    }
}

public protocol ChapterRepositoryProtocol: Sendable {
    func bulkUpsert(bookId: String, chapters: [ChapterModel]) async throws
    func loadPageKeyset(bookId: String, startIdx: Int, limit: Int) async throws -> [ChapterModel]
    func loadWindow(bookId: String, centerIndex: Int, radius: Int) async throws -> [ChapterModel]
    func getChapter(bookId: String, index: Int) async throws -> ChapterModel?
    func getChapterByUrl(bookId: String, url: String) async throws -> ChapterModel?
    func updateCacheState(bookId: String, index: Int, offset: Int64, length: Int64, isCached: Bool) async throws
    func searchChapters(bookId: String, query: String) async throws -> [ChapterModel]
    func deleteChapters(bookId: String) async throws
    func getTotalChaptersCount(bookId: String) async throws -> Int
}
