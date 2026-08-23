import Foundation

internal struct MigrationStatusInfo: Sendable, Equatable {
    internal let bookId: String
    internal let status: String
    internal let schemaVersion: Int
    internal let migratedCount: Int
    internal let updatedAt: Date

    internal init(bookId: String, status: String, schemaVersion: Int, migratedCount: Int, updatedAt: Date = Date()) {
        self.bookId = bookId
        self.status = status
        self.schemaVersion = schemaVersion
        self.migratedCount = migratedCount
        self.updatedAt = updatedAt
    }
}

internal protocol ChapterStoreProtocol: Sendable {
    func replaceFullTOC(bookId: String, chapters: [ChapterMetadataSnapshot], protectedTTS: ProtectedTTSChapter?) async throws -> SaveTOCResult
    func upsertPage(bookId: String, chapters: [ChapterMetadataSnapshot]) async throws -> SaveTOCResult
    func fetchChapter(bookId: String, index: Int, url: String) async throws -> StoredChapterSnapshot?
    func fetchOrderedTOC(bookId: String) async throws -> [StoredChapterSnapshot]
    func fetchRange(bookId: String, startIndex: Int, count: Int) async throws -> [StoredChapterSnapshot]
    func searchChapters(bookId: String, query: String) async throws -> [StoredChapterSnapshot]
    func updateCacheMetadata(bookId: String, index: Int, url: String, isCached: Bool, offset: Int64, length: Int64) async throws
    func upsertCachedChapter(bookId: String, metadata: ChapterMetadataSnapshot, isCached: Bool, offset: Int64, length: Int64) async throws
    func updateTitleTranslations(bookId: String, updates: [(index: Int, url: String, titleTrans: String)]) async throws
    func importBookMigration(bookId: String, snapshots: [StoredChapterSnapshot], statusInfo: MigrationStatusInfo) async throws
    func countChapters(bookId: String) async throws -> Int
    func getMigrationStatus(bookId: String) async throws -> MigrationStatusInfo?
    func updateMigrationStatus(bookId: String, status: String, migratedCount: Int) async throws
    func deleteBook(bookId: String) async throws
    func checkpointAndClose() async
}
