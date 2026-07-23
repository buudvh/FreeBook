import Foundation
#if canImport(SQLite3)
import SQLite3
#elseif canImport(CSQLite3)
import CSQLite3
#elseif canImport(sqlite3)
import sqlite3
#endif

public actor ChapterSQLiteRepository: ChapterRepositoryProtocol {
    private var db: OpaquePointer?

    // Cached Prepared Statements cho các câu lệnh cố định
    private var upsertStmt: OpaquePointer?
    private var loadKeysetStmt: OpaquePointer?
    private var loadWindowStmt: OpaquePointer?
    private var getChapterStmt: OpaquePointer?
    private var updateCacheStmt: OpaquePointer?
    private var deleteStmt: OpaquePointer?
    private var totalCountStmt: OpaquePointer?

    public static func make(customURL: URL? = nil) async throws -> any ChapterRepositoryProtocol {
        let repo = ChapterSQLiteRepository(customURL: customURL)
        try await repo.setupDatabaseSchema()
        return repo
    }

    public init(customURL: URL? = nil) {
        let targetURL: URL
        if let customURL = customURL {
            targetURL = customURL
        } else {
            let appSupportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
            targetURL = appSupportURL.appendingPathComponent("library.db")
        }

        var dbPointer: OpaquePointer?
        if sqlite3_open(targetURL.path, &dbPointer) != SQLITE_OK {
            AppLogger.shared.log("❌ [ChapterSQLiteRepository] Không thể mở kết nối CSDL library.db")
            self.db = nil
        } else {
            self.db = dbPointer
            ChapterSQLiteRepository.setupDatabaseSchemaSync(db: dbPointer)
        }
    }

    deinit {
        sqlite3_finalize(upsertStmt)
        sqlite3_finalize(loadKeysetStmt)
        sqlite3_finalize(loadWindowStmt)
        sqlite3_finalize(getChapterStmt)
        sqlite3_finalize(updateCacheStmt)
        sqlite3_finalize(deleteStmt)
        sqlite3_finalize(totalCountStmt)

        if let db = db {
            let rc = sqlite3_close(db)
            if rc != SQLITE_OK {
                AppLogger.shared.log("⚠️ [ChapterSQLiteRepository] sqlite3_close trả về mã lỗi: \(rc)")
            }
        }
    }

    public func setupDatabaseSchema() async throws {
        ChapterSQLiteRepository.setupDatabaseSchemaSync(db: db)
    }

    private nonisolated static func setupDatabaseSchemaSync(db: OpaquePointer?) {
        guard let db = db else { return }

        // Cấu hình PRAGMAs tối ưu hiệu năng WAL Mode & xử lý Lock Contention
        sqlite3_exec(db, "PRAGMA journal_mode = WAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA synchronous = NORMAL;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA foreign_keys = ON;", nil, nil, nil)
        sqlite3_exec(db, "PRAGMA busy_timeout = 5000;", nil, nil, nil)

        // Tạo bảng chapters (Idempotent)
        let createTableSQL = """
        CREATE TABLE IF NOT EXISTS chapters (
            id TEXT PRIMARY KEY,
            book_id TEXT NOT NULL,
            idx INTEGER NOT NULL,
            title TEXT NOT NULL,
            url TEXT NOT NULL,
            is_cached INTEGER DEFAULT 0,
            offset INTEGER DEFAULT 0,
            length INTEGER DEFAULT 0,
            host TEXT,
            title_trans TEXT
        );
        """
        sqlite3_exec(db, createTableSQL, nil, nil, nil)

        // Tạo các chỉ mục Index (Idempotent)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_chapters_book_idx ON chapters(book_id, idx);", nil, nil, nil)
        sqlite3_exec(db, "CREATE INDEX IF NOT EXISTS idx_chapters_book_cached ON chapters(book_id, is_cached);", nil, nil, nil)
    }

    private func getOrPrepare(_ statement: inout OpaquePointer?, sql: String) -> OpaquePointer? {
        if statement == nil {
            guard let db = db else { return nil }
            if sqlite3_prepare_v2(db, sql, -1, &statement, nil) != SQLITE_OK {
                let errorMsg = String(cString: sqlite3_errmsg(db))
                AppLogger.shared.log("❌ [ChapterSQLiteRepository] Lỗi prepare statement: \(errorMsg)")
                return nil
            }
        }
        return statement
    }

    public func bulkUpsert(bookId: String, chapters: [ChapterModel]) async throws {
        guard let db = db, !chapters.isEmpty else { return }

        let upsertSQL = """
        INSERT INTO chapters (id, book_id, idx, title, url, is_cached, offset, length, host, title_trans)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            idx = excluded.idx,
            title = CASE WHEN excluded.title != '' THEN excluded.title ELSE chapters.title END,
            url = CASE WHEN excluded.url != '' THEN excluded.url ELSE chapters.url END,
            is_cached = CASE WHEN excluded.is_cached = 1 THEN 1 ELSE chapters.is_cached END,
            offset = CASE WHEN excluded.is_cached = 1 THEN excluded.offset ELSE chapters.offset END,
            length = CASE WHEN excluded.is_cached = 1 THEN excluded.length ELSE chapters.length END,
            host = COALESCE(excluded.host, chapters.host),
            title_trans = COALESCE(excluded.title_trans, chapters.title_trans);
        """

        guard let stmt = getOrPrepare(&upsertStmt, sql: upsertSQL) else { return }

        sqlite3_exec(db, "BEGIN TRANSACTION;", nil, nil, nil)
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        for item in chapters {
            sqlite3_reset(stmt)
            sqlite3_bind_text(stmt, 1, item.id, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, item.bookId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(item.index))
            sqlite3_bind_text(stmt, 4, item.title, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, item.url, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int(stmt, 6, item.isCached ? 1 : 0)
            sqlite3_bind_int64(stmt, 7, item.offset)
            sqlite3_bind_int64(stmt, 8, item.length)
            if let host = item.host {
                sqlite3_bind_text(stmt, 9, host, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            if let titleTrans = item.titleTrans {
                sqlite3_bind_text(stmt, 10, titleTrans, -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }

            if sqlite3_step(stmt) != SQLITE_DONE {
                AppLogger.shared.log("❌ [ChapterSQLiteRepository] Lỗi step bulkUpsert cho chapter index \(item.index)")
            }
        }
        sqlite3_reset(stmt)
        sqlite3_exec(db, "COMMIT TRANSACTION;", nil, nil, nil)
    }

    public func loadWindow(bookId: String, centerIndex: Int, radius: Int) async throws -> [ChapterModel] {
        let minIdx = max(0, centerIndex - radius)
        let maxIdx = centerIndex + radius

        let sql = """
        SELECT id, book_id, idx, title, url, is_cached, offset, length, host, title_trans
        FROM chapters
        WHERE book_id = ? AND idx BETWEEN ? AND ?
        ORDER BY idx ASC;
        """

        guard let stmt = getOrPrepare(&loadWindowStmt, sql: sql) else { return [] }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, bookId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(minIdx))
        sqlite3_bind_int(stmt, 3, Int32(maxIdx))

        var results: [ChapterModel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let model = parseChapterRow(stmt) {
                results.append(model)
            }
        }
        sqlite3_reset(stmt)
        return results
    }

    public func loadPageKeyset(bookId: String, startIdx: Int, limit: Int) async throws -> [ChapterModel] {
        let sql = """
        SELECT id, book_id, idx, title, url, is_cached, offset, length, host, title_trans
        FROM chapters
        WHERE book_id = ? AND idx >= ?
        ORDER BY idx ASC
        LIMIT ?;
        """

        guard let stmt = getOrPrepare(&loadKeysetStmt, sql: sql) else { return [] }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, bookId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(startIdx))
        sqlite3_bind_int(stmt, 3, Int32(limit))

        var results: [ChapterModel] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let model = parseChapterRow(stmt) {
                results.append(model)
            }
        }
        sqlite3_reset(stmt)
        return results
    }

    public func getChapter(bookId: String, index: Int) async throws -> ChapterModel? {
        let sql = """
        SELECT id, book_id, idx, title, url, is_cached, offset, length, host, title_trans
        FROM chapters
        WHERE book_id = ? AND idx = ?
        LIMIT 1;
        """

        guard let stmt = getOrPrepare(&getChapterStmt, sql: sql) else { return nil }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, bookId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 2, Int32(index))

        var result: ChapterModel? = nil
        if sqlite3_step(stmt) == SQLITE_ROW {
            result = parseChapterRow(stmt)
        }
        sqlite3_reset(stmt)
        return result
    }

    public func getChapterByUrl(bookId: String, url: String) async throws -> ChapterModel? {
        guard let db = db else { return nil }

        let sql = """
        SELECT id, book_id, idx, title, url, is_cached, offset, length, host, title_trans
        FROM chapters
        WHERE book_id = ? AND url = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        var result: ChapterModel? = nil

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, bookId, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, url, -1, SQLITE_TRANSIENT)

            if sqlite3_step(statement) == SQLITE_ROW {
                result = parseChapterRow(statement)
            }
            sqlite3_finalize(statement)
        }
        return result
    }

    public func updateCacheState(bookId: String, index: Int, offset: Int64, length: Int64, isCached: Bool) async throws {
        let sql = """
        UPDATE chapters
        SET is_cached = ?, offset = ?, length = ?
        WHERE book_id = ? AND idx = ?;
        """

        guard let stmt = getOrPrepare(&updateCacheStmt, sql: sql) else { return }
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

        sqlite3_reset(stmt)
        sqlite3_bind_int(stmt, 1, isCached ? 1 : 0)
        sqlite3_bind_int64(stmt, 2, offset)
        sqlite3_bind_int64(stmt, 3, length)
        sqlite3_bind_text(stmt, 4, bookId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int(stmt, 5, Int32(index))

        sqlite3_step(stmt)
        sqlite3_reset(stmt)
    }

    public func searchChapters(bookId: String, query: String) async throws -> [ChapterModel] {
        guard let db = db else { return [] }

        // Tìm kiếm câu lệnh động: Biên dịch ad-hoc và finalize ngay
        let sql = """
        SELECT id, book_id, idx, title, url, is_cached, offset, length, host, title_trans
        FROM chapters
        WHERE book_id = ? AND title LIKE ?
        ORDER BY idx ASC;
        """

        var statement: OpaquePointer?
        var results: [ChapterModel] = []

        if sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK {
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, bookId, -1, SQLITE_TRANSIENT)
            let searchPattern = "%\(query)%"
            sqlite3_bind_text(statement, 2, searchPattern, -1, SQLITE_TRANSIENT)

            while sqlite3_step(statement) == SQLITE_ROW {
                if let model = parseChapterRow(statement) {
                    results.append(model)
                }
            }
            sqlite3_finalize(statement)
        }
        return results
    }

    public func deleteChapters(bookId: String) async throws {
        let sql = "DELETE FROM chapters WHERE book_id = ?;"
        guard let stmt = getOrPrepare(&deleteStmt, sql: sql) else { return }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, bookId, -1, SQLITE_TRANSIENT)
        sqlite3_step(stmt)
        sqlite3_reset(stmt)
    }

    public func getTotalChaptersCount(bookId: String) async throws -> Int {
        let sql = "SELECT COUNT(*) FROM chapters WHERE book_id = ?;"
        guard let stmt = getOrPrepare(&totalCountStmt, sql: sql) else { return 0 }

        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_reset(stmt)
        sqlite3_bind_text(stmt, 1, bookId, -1, SQLITE_TRANSIENT)

        var count = 0
        if sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int(stmt, 0))
        }
        sqlite3_reset(stmt)
        return count
    }

    private func parseChapterRow(_ statement: OpaquePointer?) -> ChapterModel? {
        guard let statement = statement else { return nil }

        let id = String(cString: sqlite3_column_text(statement, 0))
        let bookId = String(cString: sqlite3_column_text(statement, 1))
        let idx = Int(sqlite3_column_int(statement, 2))
        let title = String(cString: sqlite3_column_text(statement, 3))
        let url = String(cString: sqlite3_column_text(statement, 4))
        let isCached = sqlite3_column_int(statement, 5) != 0
        let offset = sqlite3_column_int64(statement, 6)
        let length = sqlite3_column_int64(statement, 7)

        var host: String? = nil
        if let hostText = sqlite3_column_text(statement, 8) {
            host = String(cString: hostText)
        }

        var titleTrans: String? = nil
        if let transText = sqlite3_column_text(statement, 9) {
            titleTrans = String(cString: transText)
        }

        return ChapterModel(
            id: id,
            bookId: bookId,
            index: idx,
            title: title,
            url: url,
            isCached: isCached,
            offset: offset,
            length: length,
            host: host,
            titleTrans: titleTrans
        )
    }
}
