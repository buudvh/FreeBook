import Foundation
import SQLite3

/// Đọc sqlite3 thô bảng SwiftData cũ (`ZEXTENSION`, `ZREPOSITORY`) cho `LegacyExtensionSQLiteMigrator`.
///
/// Chỉ dùng **một lần** lúc khởi động, trước khi `ModelContainer` mở `library.db`. Tên bảng/cột là giả định về
/// cách SwiftData đặt tên (`Z` + tên thuộc tính viết hoa, khoá `Z_PK`) — vì vậy mọi truy vấn chọn cột **theo
/// tên** sau khi kiểm `PRAGMA table_info`, không bao giờ theo vị trí.
final class LegacyExtensionSQLiteReader {
    /// Giá trị một ô, đủ cho các cột TEXT/INTEGER của hai bảng cũ.
    enum Value: Sendable {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null

        var string: String? {
            switch self {
            case .text(let value): return value
            case .integer(let value): return String(value)
            case .real(let value): return String(value)
            case .null: return nil
            }
        }

        var int: Int64? {
            switch self {
            case .integer(let value): return value
            case .real(let value): return Int64(value)
            case .text(let value): return Int64(value.trimmingCharacters(in: .whitespaces))
            case .null: return nil
            }
        }
    }

    private var db: OpaquePointer?

    /// Mở **không** tạo file mới (`SQLITE_OPEN_READWRITE` không kèm `CREATE`) — chỉ chạy `SELECT`/`PRAGMA` đọc.
    /// Dùng READWRITE thay READONLY để file ở chế độ WAL vẫn mở được dù chưa có `-shm`.
    init?(url: URL) {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let code = sqlite3_errcode(handle)
            sqlite3_close_v2(handle)
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Không mở được \(url.lastPathComponent) (sqlite \(code))")
            return nil
        }
        sqlite3_busy_timeout(handle, 5000)
        db = handle
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    /// Tạo bản chép đầy đủ của `source` tại `destination` bằng `VACUUM INTO` (gồm cả sách — đây là lưới an toàn).
    ///
    /// Chép vào file `.tmp` rồi mới đổi tên ⇒ crash giữa chừng không để lại một "bản chép" dở dang mà lần sau
    /// tưởng là hợp lệ. Bản chép được đưa về `journal_mode=DELETE` để là một file tự đủ.
    static func makeCopy(of source: URL, to destination: URL) -> Bool {
        let fm = FileManager.default
        let temp = destination.appendingPathExtension("tmp")
        try? fm.removeItem(at: temp)

        var handle: OpaquePointer?
        guard sqlite3_open_v2(source.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
            let code = sqlite3_errcode(handle)
            sqlite3_close_v2(handle)
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Không mở được library.db để chép (sqlite \(code))")
            return false
        }
        sqlite3_busy_timeout(handle, 5000)
        _ = exec(handle, "PRAGMA wal_checkpoint(TRUNCATE);", label: "wal_checkpoint")
        let escaped = temp.path.replacingOccurrences(of: "'", with: "''")
        let copied = exec(handle, "VACUUM INTO '\(escaped)';", label: "VACUUM INTO")
        sqlite3_close_v2(handle)
        guard copied else {
            try? fm.removeItem(at: temp)
            return false
        }

        var copyHandle: OpaquePointer?
        if sqlite3_open_v2(temp.path, &copyHandle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            _ = exec(copyHandle, "PRAGMA journal_mode=DELETE;", label: "journal_mode")
        }
        sqlite3_close_v2(copyHandle)

        do {
            try fm.moveItem(at: temp, to: destination)
            return true
        } catch {
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Không đổi tên được bản chép library.db: \(error.localizedDescription)")
            try? fm.removeItem(at: temp)
            return false
        }
    }

    /// Tên mọi bảng trong `sqlite_master`; `nil` khi truy vấn lỗi.
    func tableNames() -> Set<String>? {
        guard let rows = query("SELECT name FROM sqlite_master WHERE type = 'table';", columnCount: 1) else { return nil }
        return Set(rows.compactMap { $0.first?.string })
    }

    /// Tên cột thật của một bảng (`PRAGMA table_info`, cột thứ 2 là `name`); `nil` khi truy vấn lỗi.
    func columns(of table: String) -> [String]? {
        guard let rows = query("PRAGMA table_info(\(table));", columnCount: 3) else { return nil }
        return rows.compactMap { $0.count > 1 ? $0[1].string : nil }
    }

    /// `SELECT` đúng các cột cho trước, trả mỗi hàng dạng `[tên cột: giá trị]`. Tên bảng/cột là hằng trong code
    /// (đã đối chiếu `table_info`), không bao giờ đến từ dữ liệu.
    func rows(from table: String, columns: [String], orderBy: String? = nil) -> [[String: Value]]? {
        guard !columns.isEmpty else { return [] }
        var sql = "SELECT \(columns.joined(separator: ", ")) FROM \(table)"
        if let orderBy { sql += " ORDER BY \(orderBy)" }
        guard let raw = query(sql + ";", columnCount: columns.count) else { return nil }
        return raw.map { values in
            var row: [String: Value] = [:]
            for (index, name) in columns.enumerated() where index < values.count {
                row[name] = values[index]
            }
            return row
        }
    }

    // MARK: - Nội bộ

    private func query(_ sql: String, columnCount: Int) -> [[Value]]? {
        guard let db else { return nil }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] Lỗi chuẩn bị truy vấn (sqlite \(sqlite3_errcode(db))): \(sql)")
            sqlite3_finalize(stmt)
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        var result: [[Value]] = []
        while true {
            let step = sqlite3_step(stmt)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                AppLogger.shared.log("❌ 🧩 [ExtMigrate] Lỗi đọc hàng (sqlite \(step)): \(sql)")
                return nil
            }
            let available = Int(sqlite3_column_count(stmt))
            var values: [Value] = []
            values.reserveCapacity(columnCount)
            for index in 0..<min(columnCount, available) {
                values.append(Self.value(stmt, Int32(index)))
            }
            result.append(values)
        }
        return result
    }

    private static func value(_ stmt: OpaquePointer?, _ index: Int32) -> Value {
        switch sqlite3_column_type(stmt, index) {
        case SQLITE_INTEGER:
            return .integer(sqlite3_column_int64(stmt, index))
        case SQLITE_FLOAT:
            return .real(sqlite3_column_double(stmt, index))
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(stmt, index) else { return .null }
            return .text(String(cString: text))
        default:
            return .null
        }
    }

    private static func exec(_ handle: OpaquePointer?, _ sql: String, label: String) -> Bool {
        var errmsg: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(handle, sql, nil, nil, &errmsg)
        guard code == SQLITE_OK else {
            let message = errmsg.map { String(cString: $0) } ?? "không rõ"
            sqlite3_free(errmsg)
            AppLogger.shared.log("❌ 🧩 [ExtMigrate] \(label) lỗi (sqlite \(code)): \(message)")
            return false
        }
        return true
    }
}
