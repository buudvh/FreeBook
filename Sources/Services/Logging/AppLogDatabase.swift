import Foundation
import SQLite3

/// Kho log **SQLite** (1.3.948) — `applicationSupport/app_logs.sqlite`, thay các file `app_logs*.txt` xoay vòng.
///
/// - Mỗi lần mở app là một **phiên** (`sessions`): version + build, máy, iOS, nhiệt / RAM / ổ trống, trình đọc TTS, trạng
///   thái cuối (`foreground` / `background` / `ended` — phiên cũ còn `foreground` ⇒ chết khi đang mở app).
/// - Dòng log (`lines`) gắn phiên; `AppLogger` ghi theo lô, mỗi lô một transaction ngắn — không giữ transaction nào lúc app
///   bị treo (LiveContainer: giữ khoá file khi bị treo là bị giết).
/// - Giữ 20 phiên, tối đa 30 MB (`prune`). Tiền tố `app_logs` ⇒ màn Dung lượng tự đếm vào loại "Nhật ký".
///
/// **Chỉ dùng trên hàng đợi của `AppLogger`** (không khoá riêng). Lỗi ở đây chỉ `print` — gọi `AppLogger.log` từ trong
/// kho log là vòng lặp.
final class AppLogDatabase {
    struct Line {
        let ts: Date
        let isError: Bool
        let text: String
    }

    struct SessionRow {
        let id: Int64
        let startedAt: Date
        let version: String
        let build: String
        let device: String
        let os: String
        let thermal: String
        let ramFreeMB: Int
        let diskFreeMB: Int
        let tts: String
        let state: String
        let lastSeen: Date
        let lineCount: Int
        let errorCount: Int
        let prevEnd: String
    }

    static let fileName = "app_logs.sqlite"

    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private static let sessionColumns = "id, started_at, version, build, device, os, thermal, ram_free_mb, disk_free_mb, "
        + "tts, state, last_seen, line_count, error_count, prev_end"

    private var db: OpaquePointer?
    private var insertLine: OpaquePointer?
    private var bumpSession: OpaquePointer?

    init?() {
        guard sqlite3_open_v2(Self.url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            print("[AppLogDatabase] Không mở được \(Self.fileName): \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "?")")
            sqlite3_close_v2(db)
            db = nil
            return nil
        }
        sqlite3_busy_timeout(db, 2000)
        // auto_vacuum chỉ có tác dụng khi đặt **trước** khi tạo bảng (file mới).
        exec("PRAGMA auto_vacuum=INCREMENTAL;")
        exec("PRAGMA journal_mode=WAL;")
        exec("PRAGMA synchronous=NORMAL;")
        guard migrate(), prepareStatements() else { return nil }
    }

    deinit {
        sqlite3_finalize(insertLine)
        sqlite3_finalize(bumpSession)
        if let db {
            sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
            sqlite3_close_v2(db)
        }
    }

    // MARK: - Lược đồ

    private func migrate() -> Bool {
        guard userVersion() < 1 else { return true }
        return exec("""
            CREATE TABLE IF NOT EXISTS sessions(
                id INTEGER PRIMARY KEY AUTOINCREMENT, started_at REAL NOT NULL,
                version TEXT NOT NULL DEFAULT '', build TEXT NOT NULL DEFAULT '', device TEXT NOT NULL DEFAULT '',
                os TEXT NOT NULL DEFAULT '', thermal TEXT NOT NULL DEFAULT '', ram_free_mb INTEGER NOT NULL DEFAULT 0,
                disk_free_mb INTEGER NOT NULL DEFAULT 0, tts TEXT NOT NULL DEFAULT '',
                state TEXT NOT NULL DEFAULT 'foreground', last_seen REAL NOT NULL DEFAULT 0,
                line_count INTEGER NOT NULL DEFAULT 0, error_count INTEGER NOT NULL DEFAULT 0, prev_end TEXT NOT NULL DEFAULT '');
            CREATE TABLE IF NOT EXISTS lines(
                id INTEGER PRIMARY KEY AUTOINCREMENT, session_id INTEGER NOT NULL, ts REAL NOT NULL,
                is_error INTEGER NOT NULL DEFAULT 0, text TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS lines_session ON lines(session_id, id);
            PRAGMA user_version=1;
            """)
    }

    private func prepareStatements() -> Bool {
        sqlite3_prepare_v2(db, "INSERT INTO lines(session_id, ts, is_error, text) VALUES(?,?,?,?)", -1, &insertLine, nil) == SQLITE_OK
            && sqlite3_prepare_v2(
                db, "UPDATE sessions SET line_count=line_count+?, error_count=error_count+?, last_seen=? WHERE id=?",
                -1, &bumpSession, nil
            ) == SQLITE_OK
    }

    // MARK: - Ghi

    func beginSession(_ info: AppLogSessionInfo, prevEnd: String) -> Int64? {
        var statement: OpaquePointer?
        let sql = "INSERT INTO sessions(started_at, version, build, device, os, thermal, ram_free_mb, disk_free_mb, tts, "
            + "state, last_seen, prev_end) VALUES(?,?,?,?,?,?,?,?,?,'foreground',?,?)"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        let now = info.startedAt.timeIntervalSince1970
        sqlite3_bind_double(statement, 1, now)
        bind(info.version, at: 2, in: statement)
        bind(info.build, at: 3, in: statement)
        bind(info.device, at: 4, in: statement)
        bind(info.os, at: 5, in: statement)
        bind(info.thermal, at: 6, in: statement)
        sqlite3_bind_int64(statement, 7, Int64(info.ramFreeMB))
        sqlite3_bind_int64(statement, 8, Int64(info.diskFreeMB))
        bind(info.tts, at: 9, in: statement)
        sqlite3_bind_double(statement, 10, now)
        bind(prevEnd, at: 11, in: statement)
        guard sqlite3_step(statement) == SQLITE_DONE else { return nil }
        return sqlite3_last_insert_rowid(db)
    }

    /// Một lô dòng = một transaction ngắn.
    @discardableResult
    func append(_ lines: [Line], sessionId: Int64) -> Bool {
        guard !lines.isEmpty, let insertLine, let bumpSession else { return false }
        guard exec("BEGIN IMMEDIATE;") else { return false }
        var errors = 0
        for line in lines {
            sqlite3_reset(insertLine)
            sqlite3_bind_int64(insertLine, 1, sessionId)
            sqlite3_bind_double(insertLine, 2, line.ts.timeIntervalSince1970)
            sqlite3_bind_int(insertLine, 3, line.isError ? 1 : 0)
            bind(line.text, at: 4, in: insertLine)
            if sqlite3_step(insertLine) != SQLITE_DONE {
                exec("ROLLBACK;")
                return false
            }
            if line.isError { errors += 1 }
        }
        sqlite3_reset(bumpSession)
        sqlite3_bind_int64(bumpSession, 1, Int64(lines.count))
        sqlite3_bind_int64(bumpSession, 2, Int64(errors))
        sqlite3_bind_double(bumpSession, 3, lines.last?.ts.timeIntervalSince1970 ?? Date().timeIntervalSince1970)
        sqlite3_bind_int64(bumpSession, 4, sessionId)
        _ = sqlite3_step(bumpSession)
        return exec("COMMIT;")
    }

    func setState(_ state: String, sessionId: Int64) {
        run("UPDATE sessions SET state=?, last_seen=? WHERE id=?") { statement in
            self.bind(state, at: 1, in: statement)
            sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
            sqlite3_bind_int64(statement, 3, sessionId)
        }
    }

    // MARK: - Đọc

    func sessions() -> [SessionRow] {
        var rows: [SessionRow] = []
        query("SELECT \(Self.sessionColumns) FROM sessions ORDER BY id DESC") { statement in
            rows.append(Self.sessionRow(statement))
        }
        return rows
    }

    func session(id: Int64) -> SessionRow? {
        var row: SessionRow?
        query("SELECT \(Self.sessionColumns) FROM sessions WHERE id=\(id)") { statement in
            row = Self.sessionRow(statement)
        }
        return row
    }

    func lastLine(sessionId: Int64) -> Line? {
        lines(sessionId: sessionId, afterId: nil, limit: 1, newestFirst: true).first?.line
    }

    /// Dòng của phiên theo trang (`afterId` = id dòng cuối trang trước).
    func lines(sessionId: Int64, afterId: Int64?, limit: Int, newestFirst: Bool = false) -> [(id: Int64, line: Line)] {
        var result: [(id: Int64, line: Line)] = []
        let order = newestFirst ? "DESC" : "ASC"
        let after = afterId.map { " AND id>\($0)" } ?? ""
        query("SELECT id, ts, is_error, text FROM lines WHERE session_id=\(sessionId)\(after) ORDER BY id \(order) LIMIT \(limit)") { statement in
            let line = Line(
                ts: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
                isError: sqlite3_column_int(statement, 2) != 0,
                text: Self.text(statement, 3)
            )
            result.append((sqlite3_column_int64(statement, 0), line))
        }
        return result
    }

    /// Dung lượng đang dùng (trang có dữ liệu) + WAL.
    var usedBytes: Int64 {
        let pages = pragmaInt("page_count") - pragmaInt("freelist_count")
        let attributes = try? FileManager.default.attributesOfItem(atPath: Self.url.path + "-wal")
        let wal = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return max(0, pages) * pragmaInt("page_size") + wal
    }

    // MARK: - Xoá + dọn

    func delete(sessionIds: [Int64]) {
        guard !sessionIds.isEmpty else { return }
        let list = sessionIds.map(String.init).joined(separator: ",")
        exec("BEGIN IMMEDIATE; DELETE FROM lines WHERE session_id IN (\(list)); DELETE FROM sessions WHERE id IN (\(list)); COMMIT;")
        exec("PRAGMA incremental_vacuum;")
    }

    func deleteAll() {
        exec("BEGIN IMMEDIATE; DELETE FROM lines; DELETE FROM sessions; COMMIT;")
        exec("PRAGMA incremental_vacuum;")
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_TRUNCATE, nil, nil)
    }

    /// Giữ `keep` phiên mới nhất, rồi bỏ phiên cũ nhất tới khi dưới `maxBytes`; không bao giờ bỏ phiên `current`. Phiên
    /// đang ghi một mình vẫn vượt ⇒ bỏ 20% số dòng cũ nhất của nó.
    func prune(keep: Int, maxBytes: Int64, current: Int64?) {
        let protected = current.map { " AND id<>\($0)" } ?? ""
        var stale: [Int64] = []
        query("SELECT id FROM sessions WHERE id NOT IN (SELECT id FROM sessions ORDER BY id DESC LIMIT \(keep))\(protected)") { statement in
            stale.append(sqlite3_column_int64(statement, 0))
        }
        delete(sessionIds: stale)
        var guardCount = 0
        while usedBytes > maxBytes, guardCount < 40 {
            guardCount += 1
            var oldest: Int64?
            query("SELECT id FROM sessions WHERE 1=1\(protected) ORDER BY id ASC LIMIT 1") { statement in
                oldest = sqlite3_column_int64(statement, 0)
            }
            if let oldest {
                delete(sessionIds: [oldest])
            } else if let current {
                trimOldestLines(sessionId: current, fraction: 0.2)
                break
            } else {
                break
            }
        }
        sqlite3_wal_checkpoint_v2(db, nil, SQLITE_CHECKPOINT_PASSIVE, nil, nil)
    }

    private func trimOldestLines(sessionId: Int64, fraction: Double) {
        let count = session(id: sessionId)?.lineCount ?? 0
        let drop = Int(Double(count) * fraction)
        guard drop > 0 else { return }
        exec("""
            BEGIN IMMEDIATE;
            DELETE FROM lines WHERE id IN (SELECT id FROM lines WHERE session_id=\(sessionId) ORDER BY id ASC LIMIT \(drop));
            UPDATE sessions SET line_count=MAX(0, line_count-\(drop)) WHERE id=\(sessionId);
            COMMIT;
            """)
        exec("PRAGMA incremental_vacuum;")
    }

    // MARK: - Tiện ích sqlite

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        var message: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(db, sql, nil, nil, &message)
        if status != SQLITE_OK {
            print("[AppLogDatabase] Lỗi SQL (\(status)): \(message.map { String(cString: $0) } ?? "?")")
            sqlite3_free(message)
            if sql.hasPrefix("BEGIN") { sqlite3_exec(db, "ROLLBACK;", nil, nil, nil) }
            return false
        }
        return true
    }

    private func run(_ sql: String, bindings: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        bindings(statement)
        _ = sqlite3_step(statement)
    }

    private func query(_ sql: String, row: (OpaquePointer?) -> Void) {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        while sqlite3_step(statement) == SQLITE_ROW { row(statement) }
    }

    private func pragmaInt(_ name: String) -> Int64 {
        var value: Int64 = 0
        query("PRAGMA \(name)") { statement in value = sqlite3_column_int64(statement, 0) }
        return value
    }

    private func userVersion() -> Int64 { pragmaInt("user_version") }

    private func bind(_ text: String, at index: Int32, in statement: OpaquePointer?) {
        sqlite3_bind_text(statement, index, text, -1, Self.transient)
    }

    private static func text(_ statement: OpaquePointer?, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func sessionRow(_ statement: OpaquePointer?) -> SessionRow {
        SessionRow(
            id: sqlite3_column_int64(statement, 0),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            version: text(statement, 2),
            build: text(statement, 3),
            device: text(statement, 4),
            os: text(statement, 5),
            thermal: text(statement, 6),
            ramFreeMB: Int(sqlite3_column_int64(statement, 7)),
            diskFreeMB: Int(sqlite3_column_int64(statement, 8)),
            tts: text(statement, 9),
            state: text(statement, 10),
            lastSeen: Date(timeIntervalSince1970: sqlite3_column_double(statement, 11)),
            lineCount: Int(sqlite3_column_int64(statement, 12)),
            errorCount: Int(sqlite3_column_int64(statement, 13)),
            prevEnd: text(statement, 14)
        )
    }
}
