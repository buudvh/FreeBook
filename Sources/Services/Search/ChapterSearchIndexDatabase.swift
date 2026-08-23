import Foundation
import SQLite3

/// Engine SQLite mức thấp của chỉ mục tìm toàn văn. **Không** thread-safe tự thân — mọi truy cập
/// đi qua actor `ChapterSearchIndex`.
///
/// Vì sao hai bảng chứ không một bảng FTS5 với cột `UNINDEXED`: xoá theo truyện
/// (`WHERE book_id = ?`) trên bảng FTS5 là full scan, mà thao tác xoá/ghi lại chạy mỗi lần cache
/// một chương. Tách `chapter_doc` (bảng thường, có UNIQUE index theo identity) khỏi `chapter_fts`
/// (chỉ một cột `content`, rowid = `doc_id`) cho phép tra identity bằng index B-tree rồi chỉ chạm
/// đúng một hàng FTS.
internal final class ChapterSearchIndexDatabase {
    /// Một hàng thô trả về từ truy vấn MATCH; việc định vị đoạn và dựng snippet nằm ở
    /// `ChapterSearchSnippetBuilder`, không phải ở tầng SQL.
    internal struct Row: Sendable {
        internal let bookId: String
        internal let chapterIndex: Int
        internal let chapterUrl: String
        internal let chapterTitle: String
        internal let content: String
    }

    private var db: OpaquePointer?
    private let dbURL: URL

    private var stmtFindDoc: OpaquePointer?
    private var stmtInsertDoc: OpaquePointer?
    private var stmtUpdateDoc: OpaquePointer?
    private var stmtDeleteFtsRow: OpaquePointer?
    private var stmtInsertFtsRow: OpaquePointer?
    private var stmtDeleteDocRow: OpaquePointer?
    private var stmtSearchAll: OpaquePointer?
    private var stmtSearchBook: OpaquePointer?
    private var stmtDeleteBookFts: OpaquePointer?
    private var stmtDeleteBookDoc: OpaquePointer?
    private var stmtCountAll: OpaquePointer?
    private var stmtCountBook: OpaquePointer?

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    internal init(dbURL: URL) throws {
        self.dbURL = dbURL
        try openAndMigrate()
        try prepareStatements()
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

    // MARK: - Mở & migrate

    private func openAndMigrate() throws {
        if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
            let code = sqlite3_errcode(db)
            throw ChapterSearchIndexPath.IndexError.databaseError(code: code)
        }
        sqlite3_busy_timeout(db, 5000)

        try requirePragma("PRAGMA journal_mode=WAL;", expected: "wal", errorCode: 501)
        try requirePragma("PRAGMA synchronous=NORMAL;", expected: nil, errorCode: 502)

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
                // `tokenize='trigram'` là tokenizer built-in duy nhất khớp được chuỗi con của chữ
                // Hán (không có khoảng trắng). Đổi tokenizer là phải xoá và dựng lại toàn bộ chỉ mục.
                let schemaSQL = """
                CREATE TABLE IF NOT EXISTS chapter_doc (
                    doc_id INTEGER PRIMARY KEY,
                    book_id TEXT NOT NULL,
                    chapter_index INTEGER NOT NULL,
                    chapter_url TEXT NOT NULL,
                    chapter_title TEXT NOT NULL,
                    indexed_at REAL NOT NULL
                );
                CREATE UNIQUE INDEX IF NOT EXISTS idx_doc_identity ON chapter_doc(book_id, chapter_index, chapter_url);
                CREATE INDEX IF NOT EXISTS idx_doc_book ON chapter_doc(book_id);
                CREATE VIRTUAL TABLE IF NOT EXISTS chapter_fts USING fts5(content, tokenize='trigram case_sensitive 0');
                PRAGMA user_version = 1;
                """
                try execRaw(schemaSQL)
                try commitTransaction()
            } catch {
                rollbackTransaction()
                throw error
            }
        }

        ChapterSearchIndexPath.applyProtection(to: dbURL)
    }

    // MARK: - Helper mức thấp

    /// Chạy một PRAGMA và xác nhận nó có hiệu lực; `expected` khác nil thì so giá trị cột 0.
    private func requirePragma(_ sql: String, expected: String?, errorCode: Int32) throws {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw ChapterSearchIndexPath.IndexError.databaseError(code: errorCode)
        }
        let step = sqlite3_step(stmt)
        var ok = step == SQLITE_ROW || step == SQLITE_DONE
        if ok, let expected {
            let value = step == SQLITE_ROW ? columnText(stmt, 0).lowercased() : ""
            ok = value == expected
        }
        sqlite3_finalize(stmt)
        if !ok { throw ChapterSearchIndexPath.IndexError.databaseError(code: errorCode) }
    }

    private func execRaw(_ sql: String) throws {
        var errmsg: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errmsg) != SQLITE_OK {
            sqlite3_free(errmsg)
            let code = sqlite3_errcode(db)
            throw ChapterSearchIndexPath.IndexError.databaseError(code: code)
        }
    }

    private func bindText(_ stmt: OpaquePointer?, _ index: Int32, _ string: String) throws {
        guard let stmt else { throw ChapterSearchIndexPath.IndexError.databaseError(code: 401) }
        let res = sqlite3_bind_text(stmt, index, (string as NSString).utf8String, -1, Self.transientDestructor)
        if res != SQLITE_OK { throw ChapterSearchIndexPath.IndexError.databaseError(code: res) }
    }

    private func bindInt32(_ stmt: OpaquePointer?, _ index: Int32, _ val: Int32) throws {
        guard let stmt else { throw ChapterSearchIndexPath.IndexError.databaseError(code: 401) }
        let res = sqlite3_bind_int(stmt, index, val)
        if res != SQLITE_OK { throw ChapterSearchIndexPath.IndexError.databaseError(code: res) }
    }

    private func bindInt64(_ stmt: OpaquePointer?, _ index: Int32, _ val: Int64) throws {
        guard let stmt else { throw ChapterSearchIndexPath.IndexError.databaseError(code: 401) }
        let res = sqlite3_bind_int64(stmt, index, val)
        if res != SQLITE_OK { throw ChapterSearchIndexPath.IndexError.databaseError(code: res) }
    }

    private func bindDouble(_ stmt: OpaquePointer?, _ index: Int32, _ val: Double) throws {
        guard let stmt else { throw ChapterSearchIndexPath.IndexError.databaseError(code: 401) }
        let res = sqlite3_bind_double(stmt, index, val)
        if res != SQLITE_OK { throw ChapterSearchIndexPath.IndexError.databaseError(code: res) }
    }

    private func prepareOne(_ sql: String, _ stmtPtr: inout OpaquePointer?) throws {
        if sqlite3_prepare_v2(db, sql, -1, &stmtPtr, nil) != SQLITE_OK {
            let code = sqlite3_errcode(db)
            throw ChapterSearchIndexPath.IndexError.databaseError(code: code)
        }
    }

    private func columnText(_ stmt: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(stmt, index) else { return "" }
        return String(cString: cString)
    }

    private func finalizeStatements() {
        let stmts = [
            stmtFindDoc, stmtInsertDoc, stmtUpdateDoc,
            stmtDeleteFtsRow, stmtInsertFtsRow, stmtDeleteDocRow,
            stmtSearchAll, stmtSearchBook,
            stmtDeleteBookFts, stmtDeleteBookDoc,
            stmtCountAll, stmtCountBook
        ]
        for stmt in stmts {
            if let stmt { sqlite3_finalize(stmt) }
        }
    }

    internal func beginTransaction() throws {
        try execRaw("BEGIN IMMEDIATE;")
    }

    internal func commitTransaction() throws {
        try execRaw("COMMIT;")
    }

    internal func rollbackTransaction() {
        try? execRaw("ROLLBACK;")
    }

    // MARK: - Prepare

    private func prepareStatements() throws {
        try prepareOne("SELECT doc_id FROM chapter_doc WHERE book_id = ? AND chapter_index = ? AND chapter_url = ? LIMIT 1;", &stmtFindDoc)
        try prepareOne("""
        INSERT INTO chapter_doc (book_id, chapter_index, chapter_url, chapter_title, indexed_at)
        VALUES (?, ?, ?, ?, ?);
        """, &stmtInsertDoc)
        try prepareOne("UPDATE chapter_doc SET chapter_title = ?, indexed_at = ? WHERE doc_id = ?;", &stmtUpdateDoc)
        try prepareOne("DELETE FROM chapter_fts WHERE rowid = ?;", &stmtDeleteFtsRow)
        try prepareOne("INSERT INTO chapter_fts (rowid, content) VALUES (?, ?);", &stmtInsertFtsRow)
        try prepareOne("DELETE FROM chapter_doc WHERE doc_id = ?;", &stmtDeleteDocRow)

        // Không đặt alias cho `chapter_fts`: FTS5 nhận `MATCH` theo **tên bảng**, đặt alias là
        // SQLite báo "no such column".
        let searchColumns = "chapter_doc.book_id, chapter_doc.chapter_index, chapter_doc.chapter_url, chapter_doc.chapter_title, chapter_fts.content"
        let searchFrom = "FROM chapter_fts JOIN chapter_doc ON chapter_doc.doc_id = chapter_fts.rowid"
        try prepareOne("""
        SELECT \(searchColumns) \(searchFrom)
        WHERE chapter_fts MATCH ?
        ORDER BY rank LIMIT ?;
        """, &stmtSearchAll)
        try prepareOne("""
        SELECT \(searchColumns) \(searchFrom)
        WHERE chapter_fts MATCH ? AND chapter_doc.book_id = ?
        ORDER BY rank LIMIT ?;
        """, &stmtSearchBook)

        try prepareOne("DELETE FROM chapter_fts WHERE rowid IN (SELECT doc_id FROM chapter_doc WHERE book_id = ?);", &stmtDeleteBookFts)
        try prepareOne("DELETE FROM chapter_doc WHERE book_id = ?;", &stmtDeleteBookDoc)
        try prepareOne("SELECT COUNT(*) FROM chapter_doc;", &stmtCountAll)
        try prepareOne("SELECT COUNT(*) FROM chapter_doc WHERE book_id = ?;", &stmtCountBook)
    }

    // MARK: - Ghi

    /// Ghi (hoặc ghi lại) nội dung một chương vào chỉ mục. Toàn bộ nằm trong **một** transaction
    /// để chỉ mục không bao giờ có hàng `chapter_doc` mồ côi không có nội dung FTS.
    internal func upsert(bookId: String, chapterIndex: Int, chapterUrl: String, chapterTitle: String, content: String) throws {
        try beginTransaction()
        do {
            let existing = try findDocId(bookId: bookId, chapterIndex: chapterIndex, chapterUrl: chapterUrl)
            let now = Date().timeIntervalSince1970
            let docId: Int64
            if let existing {
                docId = existing
                sqlite3_reset(stmtUpdateDoc)
                sqlite3_clear_bindings(stmtUpdateDoc)
                try bindText(stmtUpdateDoc, 1, chapterTitle)
                try bindDouble(stmtUpdateDoc, 2, now)
                try bindInt64(stmtUpdateDoc, 3, docId)
                if sqlite3_step(stmtUpdateDoc) != SQLITE_DONE {
                    throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
                }
                sqlite3_reset(stmtUpdateDoc)

                sqlite3_reset(stmtDeleteFtsRow)
                sqlite3_clear_bindings(stmtDeleteFtsRow)
                try bindInt64(stmtDeleteFtsRow, 1, docId)
                if sqlite3_step(stmtDeleteFtsRow) != SQLITE_DONE {
                    throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
                }
                sqlite3_reset(stmtDeleteFtsRow)
            } else {
                sqlite3_reset(stmtInsertDoc)
                sqlite3_clear_bindings(stmtInsertDoc)
                try bindText(stmtInsertDoc, 1, bookId)
                try bindInt32(stmtInsertDoc, 2, Int32(chapterIndex))
                try bindText(stmtInsertDoc, 3, chapterUrl)
                try bindText(stmtInsertDoc, 4, chapterTitle)
                try bindDouble(stmtInsertDoc, 5, now)
                if sqlite3_step(stmtInsertDoc) != SQLITE_DONE {
                    throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
                }
                sqlite3_reset(stmtInsertDoc)
                docId = sqlite3_last_insert_rowid(db)
            }

            sqlite3_reset(stmtInsertFtsRow)
            sqlite3_clear_bindings(stmtInsertFtsRow)
            try bindInt64(stmtInsertFtsRow, 1, docId)
            try bindText(stmtInsertFtsRow, 2, content)
            if sqlite3_step(stmtInsertFtsRow) != SQLITE_DONE {
                throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
            }
            sqlite3_reset(stmtInsertFtsRow)

            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    private func findDocId(bookId: String, chapterIndex: Int, chapterUrl: String) throws -> Int64? {
        sqlite3_reset(stmtFindDoc)
        sqlite3_clear_bindings(stmtFindDoc)
        try bindText(stmtFindDoc, 1, bookId)
        try bindInt32(stmtFindDoc, 2, Int32(chapterIndex))
        try bindText(stmtFindDoc, 3, chapterUrl)
        var result: Int64?
        if sqlite3_step(stmtFindDoc) == SQLITE_ROW {
            result = sqlite3_column_int64(stmtFindDoc, 0)
        }
        sqlite3_reset(stmtFindDoc)
        return result
    }

    // MARK: - Xoá

    internal func deleteBook(bookId: String) throws {
        try beginTransaction()
        do {
            for stmt in [stmtDeleteBookFts, stmtDeleteBookDoc] {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
                try bindText(stmt, 1, bookId)
                if sqlite3_step(stmt) != SQLITE_DONE {
                    throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
                }
                sqlite3_reset(stmt)
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    internal func deleteChapter(bookId: String, chapterIndex: Int, chapterUrl: String) throws {
        try beginTransaction()
        do {
            if let docId = try findDocId(bookId: bookId, chapterIndex: chapterIndex, chapterUrl: chapterUrl) {
                for stmt in [stmtDeleteFtsRow, stmtDeleteDocRow] {
                    sqlite3_reset(stmt)
                    sqlite3_clear_bindings(stmt)
                    try bindInt64(stmt, 1, docId)
                    if sqlite3_step(stmt) != SQLITE_DONE {
                        throw ChapterSearchIndexPath.IndexError.databaseError(code: sqlite3_errcode(db))
                    }
                    sqlite3_reset(stmt)
                }
            }
            try commitTransaction()
        } catch {
            rollbackTransaction()
            throw error
        }
    }

    /// Xoá sạch chỉ mục rồi `VACUUM` để trả lại dung lượng ngay — người dùng tắt tính năng là để
    /// lấy lại chỗ, giữ file phình sẵn thì vô nghĩa.
    internal func clearAll() throws {
        try execRaw("DELETE FROM chapter_fts; DELETE FROM chapter_doc;")
        try? execRaw("VACUUM;")
    }

    // MARK: - Đọc

    internal func search(matchExpression: String, bookId: String?, limit: Int) throws -> [Row] {
        let stmt: OpaquePointer? = bookId == nil ? stmtSearchAll : stmtSearchBook
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        try bindText(stmt, 1, matchExpression)
        if let bookId {
            try bindText(stmt, 2, bookId)
            try bindInt32(stmt, 3, Int32(limit))
        } else {
            try bindInt32(stmt, 2, Int32(limit))
        }
        var rows: [Row] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(Row(
                bookId: columnText(stmt, 0),
                chapterIndex: Int(sqlite3_column_int(stmt, 1)),
                chapterUrl: columnText(stmt, 2),
                chapterTitle: columnText(stmt, 3),
                content: columnText(stmt, 4)
            ))
        }
        sqlite3_reset(stmt)
        return rows
    }

    internal func countDocuments(bookId: String?) throws -> Int {
        let stmt: OpaquePointer? = bookId == nil ? stmtCountAll : stmtCountBook
        sqlite3_reset(stmt)
        sqlite3_clear_bindings(stmt)
        if let bookId {
            try bindText(stmt, 1, bookId)
        }
        var count = 0
        if sqlite3_step(stmt) == SQLITE_ROW {
            count = Int(sqlite3_column_int64(stmt, 0))
        }
        sqlite3_reset(stmt)
        return count
    }
}
