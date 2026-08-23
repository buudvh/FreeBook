import Foundation

internal actor ChapterStore: ChapterStoreProtocol {
    internal static let shared: ChapterStore = {
        do {
            let url = try ChapterStorePath.makeDatabaseURL()
            return try ChapterStore(dbURL: url)
        } catch {
            AppLogger.shared.log("❌ [ChapterStore] Path initialization error code: 403")
            return ChapterStore(unavailable: true)
        }
    }()

    private let database: ChapterStoreDatabase?

    internal init(dbURL: URL) throws {
        self.database = try ChapterStoreDatabase(dbURL: dbURL)
    }

    internal init(unavailable: Bool) {
        self.database = nil
    }

    internal func replaceFullTOC(bookId: String, chapters: [ChapterMetadataSnapshot], protectedTTS: ProtectedTTSChapter?) async throws -> SaveTOCResult {
        guard let database else {
            AppLogger.shared.log("[ChapterStore Save] status=failed,errorCode=503")
            throw ChapterStoreError.unavailable
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (result, reconcileMs, writeMs, parityOk) = try database.replaceFullTOC(bookId: bookId, chapters: chapters, protectedTTS: protectedTTS)
            let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let parityStr = parityOk ? "ok" : "mismatch"
            AppLogger.shared.log("[ChapterStore Save] mode=replaceFullTOC items=\(chapters.count) stored=\(result.totalChapters) inserted=\(result.inserted) updated=\(result.updated) deleted=\(result.deleted) openSchemaMs=\(String(format: "%.1f", database.openSchemaMs)) prepareMs=\(String(format: "%.1f", database.prepareMs)) reconcileMs=\(String(format: "%.1f", reconcileMs)) transactionWriteMs=\(String(format: "%.1f", writeMs)) totalMs=\(String(format: "%.1f", totalMs)) status=success parity=\(parityStr)")
            return result
        } catch {
            let errCode: Int32 = (error as? ChapterStoreError).flatMap { err in
                if case .databaseError(let code) = err { return code }
                return Int32(500)
            } ?? Int32(500)
            AppLogger.shared.log("[ChapterStore Save] status=failed,errorCode=\(errCode)")
            throw error
        }
    }

    internal func upsertPage(bookId: String, chapters: [ChapterMetadataSnapshot]) async throws -> SaveTOCResult {
        guard let database else {
            AppLogger.shared.log("[ChapterStore Save] status=failed,errorCode=503")
            throw ChapterStoreError.unavailable
        }
        let t0 = CFAbsoluteTimeGetCurrent()
        do {
            let (result, reconcileMs, writeMs, parityOk) = try database.upsertPage(bookId: bookId, chapters: chapters)
            let totalMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let parityStr = parityOk ? "ok" : "mismatch"
            AppLogger.shared.log("[ChapterStore Save] mode=upsertPage items=\(chapters.count) stored=\(result.totalChapters) inserted=\(result.inserted) updated=\(result.updated) deleted=\(result.deleted) openSchemaMs=\(String(format: "%.1f", database.openSchemaMs)) prepareMs=\(String(format: "%.1f", database.prepareMs)) reconcileMs=\(String(format: "%.1f", reconcileMs)) transactionWriteMs=\(String(format: "%.1f", writeMs)) totalMs=\(String(format: "%.1f", totalMs)) status=success parity=\(parityStr)")
            return result
        } catch {
            let errCode: Int32 = (error as? ChapterStoreError).flatMap { err in
                if case .databaseError(let code) = err { return code }
                return Int32(500)
            } ?? Int32(500)
            AppLogger.shared.log("[ChapterStore Save] status=failed,errorCode=\(errCode)")
            throw error
        }
    }

    internal func fetchChapter(bookId: String, index: Int, url: String) async throws -> StoredChapterSnapshot? {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.fetchChapter(bookId: bookId, index: index, url: url)
    }

    internal func fetchOrderedTOC(bookId: String) async throws -> [StoredChapterSnapshot] {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.fetchOrderedTOC(bookId: bookId)
    }

    internal func fetchRange(bookId: String, startIndex: Int, count: Int) async throws -> [StoredChapterSnapshot] {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.fetchRange(bookId: bookId, startIndex: startIndex, count: count)
    }

    internal func searchChapters(bookId: String, query: String) async throws -> [StoredChapterSnapshot] {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.searchChapters(bookId: bookId, query: query)
    }

    internal func updateCacheMetadata(bookId: String, index: Int, url: String, isCached: Bool, offset: Int64, length: Int64) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.updateCacheMetadata(bookId: bookId, index: index, url: url, isCached: isCached, offset: offset, length: length)
    }

    internal func upsertCachedChapter(bookId: String, metadata: ChapterMetadataSnapshot, isCached: Bool, offset: Int64, length: Int64) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.upsertCachedChapter(bookId: bookId, metadata: metadata, isCached: isCached, offset: offset, length: length)
    }

    internal func updateTitleTranslations(bookId: String, updates: [(index: Int, url: String, titleTrans: String)]) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.updateTitleTranslations(bookId: bookId, updates: updates)
    }

    internal func importBookMigration(bookId: String, snapshots: [StoredChapterSnapshot], statusInfo: MigrationStatusInfo) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.importBookMigration(bookId: bookId, snapshots: snapshots, statusInfo: statusInfo)
    }

    internal func countChapters(bookId: String) async throws -> Int {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.countChapters(bookId: bookId)
    }

    internal func getMigrationStatus(bookId: String) async throws -> MigrationStatusInfo? {
        guard let database else { throw ChapterStoreError.unavailable }
        return try database.getMigrationStatus(bookId: bookId)
    }

    internal func updateMigrationStatus(bookId: String, status: String, migratedCount: Int) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.updateMigrationStatus(bookId: bookId, status: status, migratedCount: migratedCount)
    }

    internal func deleteBook(bookId: String) async throws {
        guard let database else { throw ChapterStoreError.unavailable }
        try database.deleteBook(bookId: bookId)
        let bookHash = String(Chapter.hashUrl(bookId).prefix(8))
        AppLogger.shared.log("[ChapterStore Delete] bookIdHash: \(bookHash) | status: success")
    }

    internal func checkpointAndClose() async {
        database?.checkpointAndClose()
    }
}
