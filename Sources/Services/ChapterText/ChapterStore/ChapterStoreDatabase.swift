import Foundation
import SQLite3

internal struct CompositeKey: Hashable, Sendable {
    internal let url: String
    internal let index: Int
}

internal final class ChapterStoreDatabase {
    private var db: OpaquePointer?
    private let dbURL: URL

    internal var openSchemaMs: Double = 0
    internal var prepareMs: Double = 0

    private var stmtReplace: OpaquePointer?
    private var stmtUpsert: OpaquePointer?
    private var stmtFetchChapterByUrl: OpaquePointer?
    private var stmtFetchChapterByIndex: OpaquePointer?
    private var stmtFetchOrderedTOC: OpaquePointer?
    private var stmtFetchRange: OpaquePointer?
    private var stmtSearchChapters: OpaquePointer?
    private var stmtUpdateCacheByUrl: OpaquePointer?
    private var stmtUpdateCacheByIndex: OpaquePointer?
    private var stmtUpdateTransByUrl: OpaquePointer?
    private var stmtUpdateTransByIndex: OpaquePointer?
    private var stmtGetMigrationStatus: OpaquePointer?
    private var stmtUpdateMigrationStatus: OpaquePointer?
    private var stmtDeleteChapters: OpaquePointer?
    private var stmtDeleteMigrationStatus: OpaquePointer?
    private var stmtDeleteStaleChapter: OpaquePointer?

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(dbURL: URL) throws {
        self.dbURL = dbURL
        let t0 = CFAbsoluteTimeGetCurrent()
        try openAndMigrate()
        self.openSchemaMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0

        let tPrep0 = CFAbsoluteTimeGetCurrent()
        try prepareStatements()
        self.prepareMs = (CFAbsoluteTimeGetCurrent() - tPrep0) * 1000.0
    }

    deinit {
        checkpointAndClose()
    }

    internal func checkpointAndClose() {
        finalizeStatements()
        if let db {
            sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
            sqlite3_close_v2(db)
            self.db = nil
        }
    }

    private func openAndMigrate() throws {
        let path = dbURL.path
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }

        sqlite3_busy_timeout(db, 5000)

        // Validate WAL journal mode
        var journalStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA journal_mode=WAL;", -1, &journalStmt, nil) == SQLITE_OK {
            let step = sqlite3_step(journalStmt)
            if step == SQLITE_ROW {
                if let modeStr = sqlite3_column_text(journalStmt, 0).map({ String(cString: $0) }), modeStr.lowercased() != "wal" {
                    sqlite3_finalize(journalStmt)
                    throw ChapterStoreError.databaseError(code: 501)
                }
            } else {
                sqlite3_finalize(journalStmt)
                throw ChapterStoreError.databaseError(code: 501)
            }
            sqlite3_finalize(journalStmt)
        } else {
            throw ChapterStoreError.databaseError(code: 501)
        }

        var syncStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA synchronous=NORMAL;", -1, &syncStmt, nil) == SQLITE_OK {
            let step = sqlite3_step(syncStmt)
            sqlite3_finalize(syncStmt)
            if step != SQLITE_DONE && step != SQLITE_ROW {
                throw ChapterStoreError.databaseError(code: 502)
            }
        } else {
            throw ChapterStoreError.databaseError(code: 502)
        }

        var version: Int32 = 0
        var vStmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &vStmt, nil) == SQLITE_OK {
            if sqlite3_step(vStmt) == SQLITE_ROW {
                version = sqlite3_column_int(vStmt, 0)
            }
            sqlite3_finalize(vStmt)
        }

        if version < 1 {
            try beginTransaction()
            do {
                let schemaSQL = """
                CREATE TABLE IF NOT EXISTS chapter_metadata (
                    id TEXT PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    chapter_index INTEGER NOT NULL,
                    title TEXT NOT NULL,
                    url TEXT NOT NULL,
                    host TEXT,
                    title_trans TEXT,
                    is_cached INTEGER NOT NULL DEFAULT 0,
                    offset INTEGER NOT NULL DEFAULT 0,
                    length INTEGER NOT NULL DEFAULT 0,
                    updated_at REAL NOT NULL
                );
                CREATE INDEX IF NOT EXISTS idx_chapter_book_index ON chapter_metadata(book_id, chapter_index);
                CREATE INDEX IF NOT EXISTS idx_chapter_book_url ON chapter_metadata(book_id, url);

                CREATE TABLE IF NOT EXISTS migration_status (
                    book_id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    schema_version INTEGER NOT NULL DEFAULT 1,
                    migrated_count INTEGER NOT NULL DEFAULT 0,
                    updated_at REAL NOT NULL
                );
                PRAGMA user_version = 1;
                """
                try execRaw(schemaSQL)
                try commitTransaction()
            } catch {
                rollbackTransaction()
                throw error
            }
        }

        applyFileProtection()
    }

    internal func applyFileProtection() {
        let fm = FileManager.default
        let dbPath = dbURL.path
        let walPath = "\(dbPath)-wal"
        let shmPath = "\(dbPath)-shm"
        let attr = [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]

        try? fm.setAttributes(attr, ofItemAtPath: dbPath)
        if fm.fileExists(atPath: walPath) {
            try? fm.setAttributes(attr, ofItemAtPath: walPath)
        }
        if fm.fileExists(atPath: shmPath) {
            try? fm.setAttributes(attr, ofItemAtPath: shmPath)
        }
    }

    private func execRaw(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            sqlite3_free(errmsg)
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ string: String?) throws {
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }
        let res: Int32
        if let string {
            res = sqlite3_bind_text(stmt, index, (string as NSString).utf8String, -1, Self.transientDestructor)
        } else {
            res = sqlite3_bind_null(stmt, index)
        }
        if res != SQLITE_OK { throw ChapterStoreError.databaseError(code: res) }
    }

    private func bindInt32(_ stmt: OpaquePointer?, _ index: Int32, _ val: Int32) throws {
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }
        let res = sqlite3_bind_int(stmt, index, val)
        if res != SQLITE_OK { throw ChapterStoreError.databaseError(code: res) }
    }

    private func bindInt64(_ stmt: OpaquePointer?, _ index: Int32, _ val: Int64) throws {
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }
        let res = sqlite3_bind_int64(stmt, index, val)
        if res != SQLITE_OK { throw ChapterStoreError.databaseError(code: res) }
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ val: Double) throws {
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }
        let res = sqlite3_bind_double(stmt, index, val)
        if res != SQLITE_OK { throw ChapterStoreError.databaseError(code: res) }
    }

    private func prepareStatements() throws {
        let replaceSQL = """
        INSERT INTO chapter_metadata (id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            chapter_index = excluded.chapter_index,
            title = excluded.title,
            url = excluded.url,
            host = excluded.host,
            title_trans = coalesce(excluded.title_trans, chapter_metadata.title_trans),
            updated_at = excluded.updated_at;
        """
        try prepareOne(replaceSQL, &stmtReplace)

        let upsertSQL = replaceSQL
        try prepareOne(upsertSQL, &stmtUpsert)

        let fetchByUrlSQL = """
        SELECT id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at
        FROM chapter_metadata
        WHERE book_id = ? AND url = ?
        LIMIT 1;
        """
        try prepareOne(fetchByUrlSQL, &stmtFetchChapterByUrl)

        let fetchByIndexSQL = """
        SELECT id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at
        FROM chapter_metadata
        WHERE book_id = ? AND chapter_index = ?
        LIMIT 1;
        """
        try prepareOne(fetchByIndexSQL, &stmtFetchChapterByIndex)

        let fetchOrderedTOCSQL = """
        SELECT id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at
        FROM chapter_metadata
        WHERE book_id = ?
        ORDER BY chapter_index ASC;
        """
        try prepareOne(fetchOrderedTOCSQL, &stmtFetchOrderedTOC)

        let fetchRangeSQL = """
        SELECT id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at
        FROM chapter_metadata
        WHERE book_id = ? AND chapter_index >= ? AND chapter_index <= ?
        ORDER BY chapter_index ASC;
        """
        try prepareOne(fetchRangeSQL, &stmtFetchRange)

        let searchChaptersSQL = """
        SELECT id, book_id, chapter_index, title, url, host, title_trans, is_cached, offset, length, updated_at
        FROM chapter_metadata
        WHERE book_id = ? AND (title LIKE ? OR (title_trans IS NOT NULL AND title_trans LIKE ?))
        ORDER BY chapter_index ASC;
        """
        try prepareOne(searchChaptersSQL, &stmtSearchChapters)

        let updateCacheByUrlSQL = """
        UPDATE chapter_metadata
        SET is_cached = ?, offset = ?, length = ?, updated_at = ?
        WHERE book_id = ? AND url = ?;
        """
        try prepareOne(updateCacheByUrlSQL, &stmtUpdateCacheByUrl)

        let updateCacheByIndexSQL = """
        UPDATE chapter_metadata
        SET is_cached = ?, offset = ?, length = ?, updated_at = ?
        WHERE book_id = ? AND chapter_index = ?;
        """
        try prepareOne(updateCacheByIndexSQL, &stmtUpdateCacheByIndex)

        let updateTransByUrlSQL = """
        UPDATE chapter_metadata
        SET title_trans = ?, updated_at = ?
        WHERE book_id = ? AND url = ?;
        """
        try prepareOne(updateTransByUrlSQL, &stmtUpdateTransByUrl)

        let updateTransByIndexSQL = """
        UPDATE chapter_metadata
        SET title_trans = ?, updated_at = ?
        WHERE book_id = ? AND chapter_index = ?;
        """
        try prepareOne(updateTransByIndexSQL, &stmtUpdateTransByIndex)

        let getMigrationSQL = """
        SELECT book_id, status, schema_version, migrated_count, updated_at
        FROM migration_status
        WHERE book_id = ?
        LIMIT 1;
        """
        try prepareOne(getMigrationSQL, &stmtGetMigrationStatus)

        let updateMigrationSQL = """
        INSERT INTO migration_status (book_id, status, schema_version, migrated_count, updated_at)
        VALUES (?, ?, 1, ?, ?)
        ON CONFLICT(book_id) DO UPDATE SET
            status = excluded.status,
            migrated_count = excluded.migrated_count,
            updated_at = excluded.updated_at;
        """
        try prepareOne(updateMigrationSQL, &stmtUpdateMigrationStatus)

        let deleteChaptersSQL = "DELETE FROM chapter_metadata WHERE book_id = ?;"
        try prepareOne(deleteChaptersSQL, &stmtDeleteChapters)

        let deleteMigrationSQL = "DELETE FROM migration_status WHERE book_id = ?;"
        try prepareOne(deleteMigrationSQL, &stmtDeleteMigrationStatus)

        let deleteStaleSQL = "DELETE FROM chapter_metadata WHERE id = ? AND book_id = ?;"
        try prepareOne(deleteStaleSQL, &stmtDeleteStaleChapter)
    }

    private func prepareOne(_ sql: String, _ stmtPtr: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmtPtr, nil) != SQLITE_OK {
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }
    }

    private func finalizeStatements() {
        let stmts = [
            stmtReplace, stmtUpsert, stmtFetchChapterByUrl, stmtFetchChapterByIndex,
            stmtFetchOrderedTOC, stmtFetchRange, stmtSearchChapters,
            stmtUpdateCacheByUrl, stmtUpdateCacheByIndex, stmtUpdateTransByUrl, stmtUpdateTransByIndex,
            stmtGetMigrationStatus, stmtUpdateMigrationStatus,
            stmtDeleteChapters, stmtDeleteMigrationStatus, stmtDeleteStaleChapter
        ]
        for stmt in stmts {
            if let stmt {
                sqlite3_finalize(stmt)
            }
        }
    }

    // MARK: - Transaction Control
    func beginTransaction() throws {
        try execRaw("BEGIN IMMEDIATE;")
    }

    func commitTransaction() throws {
        try execRaw("COMMIT;")
    }

    func rollbackTransaction() {
        try? execRaw("ROLLBACK;")
    }

    // MARK: - Deterministic FNV-1a Checksum
    internal func computeDeterministicChecksum(chapters: [StoredChapterSnapshot]) -> Int64 {
        var hash: UInt64 = 14695981039346656037
        for ch in chapters {
            hash = fnv1aUpdate(hash, string: ch.id)
            hash = fnv1aUpdate(hash, string: String(ch.index))
            hash = fnv1aUpdate(hash, string: ch.url)
            hash = fnv1aUpdate(hash, string: ch.title)
            hash = fnv1aUpdate(hash, string: ch.titleTrans ?? "")
            hash = fnv1aUpdate(hash, string: ch.isCached ? "1" : "0")
            hash = fnv1aUpdate(hash, string: String(ch.offset))
            hash = fnv1aUpdate(hash, string: String(ch.length))
        }
        return Int64(bitPattern: hash)
    }

    private func fnv1aUpdate(_ currentHash: UInt64, string: String) -> UInt64 {
        var h = currentHash
        for byte in string.utf8 {
            h ^= UInt64(byte)
            h = h &* 1099511628211
        }
        return h
    }

    // MARK: - Operations
    func replaceFullTOC(bookId: String, chapters: [ChapterMetadataSnapshot], protectedTTS: ProtectedTTSChapter?) throws -> (result: SaveTOCResult, reconcileMs: Double, writeMs: Double, checksum: Int64, parityOk: Bool) {
        let tReconcile0 = CFAbsoluteTimeGetCurrent()
        let existingChapters = try fetchOrderedTOC(bookId: bookId)

        var candidateMap: [CompositeKey: [StoredChapterSnapshot]] = [:]
        for ch in existingChapters {
            let key = CompositeKey(url: ch.url, index: ch.index)
            candidateMap[key, default: []].append(ch)
        }

        var existingIDs: Set<String> = Set(existingChapters.map { $0.id })
        var matchedOrInsertedIds: Set<String> = []

        var insertedCount = 0
        var updatedCount = 0
        let now = Date().timeIntervalSince1970
        let reconcileMs = (CFAbsoluteTimeGetCurrent() - tReconcile0) * 1000.0

        let tWrite0 = CFAbsoluteTimeGetCurrent()
        try beginTransaction()
        do {
            for item in chapters {
                try Task.checkCancellation()
                let key = CompositeKey(url: item.url, index: item.index)

                let finalId: String
                let isCached: Int32
                let offset: Int64
                let length: Int64
                let finalTitleTrans: String?

                if var queue = candidateMap[key], !queue.isEmpty {
                    let existing = queue.removeFirst()
                    candidateMap[key] = queue
                    finalId = existing.id
                    isCached = existing.isCached ? 1 : 0
                    offset = existing.offset
                    length = existing.length
                    if let newTrans = item.titleTrans, !newTrans.isEmpty {
                        finalTitleTrans = newTrans
                    } else {
                        finalTitleTrans = existing.titleTrans
                    }
                    updatedCount += 1
                } else {
                    finalId = allocateNewIdExact(bookId: bookId, item: item, existingIDs: &existingIDs)
                    isCached = 0
                    offset = 0
                    length = 0
                    finalTitleTrans = item.titleTrans
                    insertedCount += 1
                }

                matchedOrInsertedIds.insert(finalId)

                guard let stmt = stmtReplace else { throw ChapterStoreError.databaseError(code: 4) }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                try bindText(stmt, 1, finalId)
                try bindText(stmt, 2, bookId)
                try bindInt32(stmt, 3, Int32(item.index))
                try bindText(stmt, 4, item.title)
                try bindText(stmt, 5, item.url)
                try bindText(stmt, 6, item.host)
                try bindText(stmt, 7, finalTitleTrans)
                try bindInt32(stmt, 8, isCached)
                try bindInt64(stmt, 9, offset)
                try bindInt64(stmt, 10, length)
                try bindDouble(stmt, 11, now)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let code = sqlite3_errcode(db)
                    throw ChapterStoreError.databaseError(code: code)
                }
            }

            // Stale Deletion using pre-prepared statement
            var deletedCount = 0
            guard let delStmt = stmtDeleteStaleChapter else { throw ChapterStoreError.databaseError(code: 402) }
            for ch in existingChapters {
                if !matchedOrInsertedIds.contains(ch.id) {
                    if let prot = protectedTTS, prot.bookId == bookId, ch.index == prot.index, (prot.url.isEmpty || ch.url == prot.url) {
                        continue
                    }
                    sqlite3_reset(delStmt)
                    sqlite3_clear_bindings(delStmt)
                    try bindText(delStmt, 1, ch.id)
                    try bindText(delStmt, 2, bookId)
                    if sqlite3_step(delStmt) == SQLITE_DONE {
                        deletedCount += 1
                    } else {
                        let code = sqlite3_errcode(db)
                        throw ChapterStoreError.databaseError(code: code)
                    }
                }
            }

            try commitTransaction()
            applyFileProtection()
            let writeMs = (CFAbsoluteTimeGetCurrent() - tWrite0) * 1000.0

            let finalTOC = try fetchOrderedTOC(bookId: bookId)
            let checksum = computeDeterministicChecksum(chapters: finalTOC)
            let parityOk = (finalTOC.count == chapters.count || (protectedTTS != nil && finalTOC.count == chapters.count + 1))
            let result = SaveTOCResult(inserted: insertedCount, updated: updatedCount, deleted: deletedCount, totalChapters: finalTOC.count)
            return (result, reconcileMs, writeMs, checksum, parityOk)
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    func upsertPage(bookId: String, chapters: [ChapterMetadataSnapshot]) throws -> (result: SaveTOCResult, reconcileMs: Double, writeMs: Double, checksum: Int64, parityOk: Bool) {
        let tReconcile0 = CFAbsoluteTimeGetCurrent()
        let existingChapters = try fetchOrderedTOC(bookId: bookId)

        var expectedKeys = Set(existingChapters.map { CompositeKey(url: $0.url, index: $0.index) })
        for item in chapters {
            expectedKeys.insert(CompositeKey(url: item.url, index: item.index))
        }
        let expectedCount = expectedKeys.count

        var candidateMap: [CompositeKey: [StoredChapterSnapshot]] = [:]
        for ch in existingChapters {
            let key = CompositeKey(url: ch.url, index: ch.index)
            candidateMap[key, default: []].append(ch)
        }
        var existingIDs: Set<String> = Set(existingChapters.map { $0.id })

        var insertedCount = 0
        var updatedCount = 0
        let now = Date().timeIntervalSince1970
        let reconcileMs = (CFAbsoluteTimeGetCurrent() - tReconcile0) * 1000.0

        let tWrite0 = CFAbsoluteTimeGetCurrent()
        try beginTransaction()
        do {
            for item in chapters {
                try Task.checkCancellation()
                let key = CompositeKey(url: item.url, index: item.index)

                let finalId: String
                let isCached: Int32
                let offset: Int64
                let length: Int64
                let finalTitleTrans: String?

                if var queue = candidateMap[key], !queue.isEmpty {
                    let existing = queue.removeFirst()
                    candidateMap[key] = queue
                    finalId = existing.id
                    isCached = existing.isCached ? 1 : 0
                    offset = existing.offset
                    length = existing.length
                    if let newTrans = item.titleTrans, !newTrans.isEmpty {
                        finalTitleTrans = newTrans
                    } else {
                        finalTitleTrans = existing.titleTrans
                    }
                    updatedCount += 1
                } else {
                    finalId = allocateNewIdExact(bookId: bookId, item: item, existingIDs: &existingIDs)
                    isCached = 0
                    offset = 0
                    length = 0
                    finalTitleTrans = item.titleTrans
                    insertedCount += 1
                }

                guard let stmt = stmtUpsert else { throw ChapterStoreError.databaseError(code: 6) }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                try bindText(stmt, 1, finalId)
                try bindText(stmt, 2, bookId)
                try bindInt32(stmt, 3, Int32(item.index))
                try bindText(stmt, 4, item.title)
                try bindText(stmt, 5, item.url)
                try bindText(stmt, 6, item.host)
                try bindText(stmt, 7, finalTitleTrans)
                try bindInt32(stmt, 8, isCached)
                try bindInt64(stmt, 9, offset)
                try bindInt64(stmt, 10, length)
                try bindDouble(stmt, 11, now)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let code = sqlite3_errcode(db)
                    throw ChapterStoreError.databaseError(code: code)
                }
            }

            try commitTransaction()
            applyFileProtection()
            let writeMs = (CFAbsoluteTimeGetCurrent() - tWrite0) * 1000.0

            let finalTOC = try fetchOrderedTOC(bookId: bookId)
            let checksum = computeDeterministicChecksum(chapters: finalTOC)
            let parityOk = (finalTOC.count == expectedCount)
            let result = SaveTOCResult(inserted: insertedCount, updated: updatedCount, deleted: 0, totalChapters: finalTOC.count)
            return (result, reconcileMs, writeMs, checksum, parityOk)
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    private func allocateNewIdExact(bookId: String, item: ChapterMetadataSnapshot, existingIDs: inout Set<String>) -> String {
        let baseId = Chapter.generateId(bookId: bookId, url: item.url, index: item.index)
        if !existingIDs.contains(baseId) {
            existingIDs.insert(baseId)
            return baseId
        }
        let fallbackBase = "\(bookId.count):\(bookId)|I:\(item.index)"
        if !existingIDs.contains(fallbackBase) {
            existingIDs.insert(fallbackBase)
            return fallbackBase
        }
        var counter = 1
        var candidate = "\(fallbackBase)_col_\(counter)"
        while existingIDs.contains(candidate) {
            counter += 1
            candidate = "\(fallbackBase)_col_\(counter)"
        }
        existingIDs.insert(candidate)
        return candidate
    }

    func fetchChapter(bookId: String, index: Int, url: String) throws -> StoredChapterSnapshot? {
        if !url.isEmpty {
            guard let stmt = stmtFetchChapterByUrl else { return nil }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            try bindText(stmt, 1, bookId)
            try bindText(stmt, 2, url)
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseRow(stmt)
            }
        } else {
            guard let stmt = stmtFetchChapterByIndex else { return nil }
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            try bindText(stmt, 1, bookId)
            try bindInt32(stmt, 2, Int32(index))
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseRow(stmt)
            }
        }
        return nil
    }

    func fetchOrderedTOC(bookId: String) throws -> [StoredChapterSnapshot] {
        guard let stmt = stmtFetchOrderedTOC else { return [] }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        try bindText(stmt, 1, bookId)

        var list: [StoredChapterSnapshot] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                list.append(parseRow(stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }
        }
        return list
    }

    func fetchRange(bookId: String, startIndex: Int, count: Int) throws -> [StoredChapterSnapshot] {
        guard let stmt = stmtFetchRange else { return [] }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        let endIndex = startIndex + count - 1
        try bindText(stmt, 1, bookId)
        try bindInt32(stmt, 2, Int32(startIndex))
        try bindInt32(stmt, 3, Int32(endIndex))

        var list: [StoredChapterSnapshot] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_ROW {
                list.append(parseRow(stmt))
            } else if step == SQLITE_DONE {
                break
            } else {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }
        }
        return list
    }

    func searchChapters(bookId: String, query: String) throws -> [StoredChapterSnapshot] {
        let pattern = "%\(query)%"
        guard let stmt = stmtSearchChapters else { return [] }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        try bindText(stmt, 1, bookId)
        try bindText(stmt, 2, pattern)
        try bindText(stmt, 3, pattern)
        var list: [StoredChapterSnapshot] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            list.append(parseRow(stmt))
        }
        return list
    }

    func updateCacheMetadata(bookId: String, index: Int, url: String, isCached: Bool, offset: Int64, length: Int64) throws {
        let useUrl = !url.isEmpty
        let stmt = useUrl ? stmtUpdateCacheByUrl : stmtUpdateCacheByIndex
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }

        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        try bindInt32(stmt, 1, isCached ? 1 : 0)
        try bindInt64(stmt, 2, offset)
        try bindInt64(stmt, 3, length)
        try bindDouble(stmt, 4, Date().timeIntervalSince1970)
        try bindText(stmt, 5, bookId)
        if useUrl {
            try bindText(stmt, 6, url)
        } else {
            try bindInt32(stmt, 6, Int32(index))
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }
    }

    func upsertCachedChapter(bookId: String, metadata: ChapterMetadataSnapshot, isCached: Bool, offset: Int64, length: Int64) throws {
        let useUrl = !metadata.url.isEmpty
        let stmt = useUrl ? stmtUpdateCacheByUrl : stmtUpdateCacheByIndex
        guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }

        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        try bindInt32(stmt, 1, isCached ? 1 : 0)
        try bindInt64(stmt, 2, offset)
        try bindInt64(stmt, 3, length)
        try bindDouble(stmt, 4, Date().timeIntervalSince1970)
        try bindText(stmt, 5, bookId)
        if useUrl {
            try bindText(stmt, 6, metadata.url)
        } else {
            try bindInt32(stmt, 6, Int32(metadata.index))
        }

        if sqlite3_step(stmt) != SQLITE_DONE {
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }

        if sqlite3_changes(db) == 0 && !metadata.title.isEmpty {
            // Row does not exist; insert real metadata row atomically
            _ = try upsertPage(bookId: bookId, chapters: [metadata])
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            try bindInt32(stmt, 1, isCached ? 1 : 0)
            try bindInt64(stmt, 2, offset)
            try bindInt64(stmt, 3, length)
            try bindDouble(stmt, 4, Date().timeIntervalSince1970)
            try bindText(stmt, 5, bookId)
            if useUrl {
                try bindText(stmt, 6, metadata.url)
            } else {
                try bindInt32(stmt, 6, Int32(metadata.index))
            }
            if sqlite3_step(stmt) != SQLITE_DONE {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }
        }
    }

    func updateTitleTranslations(bookId: String, updates: [(index: Int, url: String, titleTrans: String)]) throws {
        try beginTransaction()
        do {
            let now = Date().timeIntervalSince1970
            for item in updates {
                let useUrl = !item.url.isEmpty
                let stmt = useUrl ? stmtUpdateTransByUrl : stmtUpdateTransByIndex
                guard let stmt else { throw ChapterStoreError.databaseError(code: 401) }

                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                try bindText(stmt, 1, item.titleTrans)
                try bindDouble(stmt, 2, now)
                try bindText(stmt, 3, bookId)
                if useUrl {
                    try bindText(stmt, 4, item.url)
                } else {
                    try bindInt32(stmt, 4, Int32(item.index))
                }

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let code = sqlite3_errcode(db)
                    throw ChapterStoreError.databaseError(code: code)
                }
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    func importBookMigration(bookId: String, snapshots: [StoredChapterSnapshot], statusInfo: MigrationStatusInfo) throws {
        guard !snapshots.isEmpty else {
            let bookHash = String(Chapter.hashUrl(bookId).prefix(8))
            AppLogger.shared.log("❌ [ChapterStore Migration] Rejected empty snapshots import | bookHash=\(bookHash)")
            throw ChapterStoreError.invalidContent
        }

        try beginTransaction()
        do {
            for item in snapshots {
                guard let stmt = stmtReplace else { throw ChapterStoreError.databaseError(code: 4) }
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)

                try bindText(stmt, 1, item.id)
                try bindText(stmt, 2, bookId)
                try bindInt32(stmt, 3, Int32(item.index))
                try bindText(stmt, 4, item.title)
                try bindText(stmt, 5, item.url)
                try bindText(stmt, 6, item.host)
                try bindText(stmt, 7, item.titleTrans)
                try bindInt32(stmt, 8, item.isCached ? 1 : 0)
                try bindInt64(stmt, 9, item.offset)
                try bindInt64(stmt, 10, item.length)
                try bindDouble(stmt, 11, item.updatedAt.timeIntervalSince1970)

                if sqlite3_step(stmt) != SQLITE_DONE {
                    let code = sqlite3_errcode(db)
                    throw ChapterStoreError.databaseError(code: code)
                }
            }

            let existingChapters = try fetchOrderedTOC(bookId: bookId)
            let incomingIDs = Set(snapshots.map { $0.id })
            guard let delStmt = stmtDeleteStaleChapter else { throw ChapterStoreError.databaseError(code: 402) }
            for ch in existingChapters {
                if !incomingIDs.contains(ch.id) {
                    sqlite3_reset(delStmt)
                    sqlite3_clear_bindings(delStmt)
                    try bindText(delStmt, 1, ch.id)
                    try bindText(delStmt, 2, bookId)
                    if sqlite3_step(delStmt) != SQLITE_DONE {
                        let code = sqlite3_errcode(db)
                        throw ChapterStoreError.databaseError(code: code)
                    }
                }
            }

            guard let mStmt = stmtUpdateMigrationStatus else { throw ChapterStoreError.databaseError(code: 5) }
            sqlite3_reset(mStmt)
            sqlite3_clear_bindings(mStmt)

            try bindText(mStmt, 1, statusInfo.bookId)
            try bindText(mStmt, 2, statusInfo.status)
            try bindInt32(mStmt, 3, Int32(statusInfo.migratedCount))
            try bindDouble(mStmt, 4, statusInfo.updatedAt.timeIntervalSince1970)

            if sqlite3_step(mStmt) != SQLITE_DONE {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }

            try commitTransaction()
            applyFileProtection()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    func fetchCountAndChecksum(bookId: String) throws -> (count: Int, checksum: Int64) {
        let chapters = try fetchOrderedTOC(bookId: bookId)
        let checksum = computeDeterministicChecksum(chapters: chapters)
        return (chapters.count, checksum)
    }

    func getMigrationStatus(bookId: String) throws -> MigrationStatusInfo? {
        guard let stmt = stmtGetMigrationStatus else { return nil }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        try bindText(stmt, 1, bookId)

        if sqlite3_step(stmt) == SQLITE_ROW {
            let bId = String(cString: sqlite3_column_text(stmt, 0))
            let st = String(cString: sqlite3_column_text(stmt, 1))
            let ver = Int(sqlite3_column_int(stmt, 2))
            let cnt = Int(sqlite3_column_int(stmt, 3))
            let upd = sqlite3_column_double(stmt, 4)
            return MigrationStatusInfo(bookId: bId, status: st, schemaVersion: ver, migratedCount: cnt, updatedAt: Date(timeIntervalSince1970: upd))
        }
        return nil
    }

    func updateMigrationStatus(bookId: String, status: String, migratedCount: Int) throws {
        guard let stmt = stmtUpdateMigrationStatus else { return }
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)

        try bindText(stmt, 1, bookId)
        try bindText(stmt, 2, status)
        try bindInt32(stmt, 3, Int32(migratedCount))
        try bindDouble(stmt, 4, Date().timeIntervalSince1970)

        if sqlite3_step(stmt) != SQLITE_DONE {
            let code = sqlite3_errcode(db)
            throw ChapterStoreError.databaseError(code: code)
        }
    }

    func deleteBook(bookId: String) throws {
        guard let stmt1 = stmtDeleteChapters, let stmt2 = stmtDeleteMigrationStatus else { return }
        try beginTransaction()
        do {
            sqlite3_reset(stmt1)
            sqlite3_clear_bindings(stmt1)
            try bindText(stmt1, 1, bookId)
            if sqlite3_step(stmt1) != SQLITE_DONE {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }

            sqlite3_reset(stmt2)
            sqlite3_clear_bindings(stmt2)
            try bindText(stmt2, 1, bookId)
            if sqlite3_step(stmt2) != SQLITE_DONE {
                let code = sqlite3_errcode(db)
                throw ChapterStoreError.databaseError(code: code)
            }

            try commitTransaction()
            applyFileProtection()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    private func parseRow(_ stmt: OpaquePointer) -> StoredChapterSnapshot {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let bookId = String(cString: sqlite3_column_text(stmt, 1))
        let index = Int(sqlite3_column_int(stmt, 2))
        let title = String(cString: sqlite3_column_text(stmt, 3))
        let url = String(cString: sqlite3_column_text(stmt, 4))
        let host: String? = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let titleTrans: String? = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let isCached = sqlite3_column_int(stmt, 7) != 0
        let offset = sqlite3_column_int64(stmt, 8)
        let length = sqlite3_column_int64(stmt, 9)
        let updatedAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 10))

        return StoredChapterSnapshot(
            id: id,
            bookId: bookId,
            title: title,
            url: url,
            index: index,
            host: host,
            titleTrans: titleTrans,
            isCached: isCached,
            offset: offset,
            length: length,
            updatedAt: updatedAt
        )
    }
}
