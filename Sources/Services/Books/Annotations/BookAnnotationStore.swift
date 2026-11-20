import Foundation

/// Engine lưu trữ mức thấp — chủ **duy nhất** của thư mục `applicationSupportDirectory/annotations/` (1.3.1040): mỗi truyện
/// một file `<sha256(bookId)>.json` = `BookAnnotations` (dấu trang + ghi chú). Không giữ trạng thái; đọc / ghi đồng bộ, gọi
/// được từ luồng bất kỳ (ghi tuần tự qua `lock`). `BookAnnotationRepository` là lối của View.
///
/// Đi theo truyện: xoá truyện (`BookStorageManager.deleteBookSideData`), đổi nguồn (`BookSourceMigrator` chép / xoá), sao
/// lưu (`BackupAnnotationArchiver`, entry `library/annotations.json`), Dung lượng (`StorageUsageCategory.annotations`),
/// Dọn rác (file của truyện không còn trong thư viện, `JunkScanner.deletedBookCandidates`).
///
/// Ghi `.atomic`. Bản rỗng ⇒ xoá file. File đọc lỗi (JSON hỏng) ⇒ đổi tên sang `.broken-<thời điểm>.json` trước khi ghi đè,
/// không mất dữ liệu âm thầm.
enum BookAnnotationStore {
    static let directoryName = "annotations"

    private static let lock = NSLock()

    static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Tên file = SHA-256 hex của `bookId` (`String.sha256()`, cùng hàm băm của `ComicOfflineStore` / `JunkScanner`).
    static func fileURL(bookId: String) -> URL {
        directoryURL.appendingPathComponent("\(bookId.sha256()).json")
    }

    // MARK: - Đọc / ghi

    static func load(bookId: String) -> BookAnnotations {
        guard !bookId.isEmpty else { return BookAnnotations() }
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(bookId: bookId)
    }

    /// Ghi đè bản của truyện (rỗng ⇒ xoá file). Lỗi chỉ log `❌`.
    static func save(_ annotations: BookAnnotations, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        saveLocked(annotations, bookId: bookId)
    }

    /// Đổi nguồn: gộp bản của truyện cũ vào truyện đích (mục của đích giữ nguyên). Không xoá bản cũ.
    static func copy(from oldBookId: String, to newBookId: String) {
        guard !oldBookId.isEmpty, !newBookId.isEmpty, oldBookId != newBookId else { return }
        lock.lock()
        defer { lock.unlock() }
        let source = loadLocked(bookId: oldBookId)
        guard !source.isEmpty else { return }
        let merged = loadLocked(bookId: newBookId).merging(source)
        saveLocked(merged, bookId: newBookId)
        AppLogger.shared.log("🔖 [Annotations] Chép \(source.bookmarks.count) dấu trang, \(source.notes.count) ghi chú sang truyện mới")
    }

    /// Xoá bản của một truyện. Trả `false` khi file còn mà xoá lỗi (nơi gọi đưa vào hàng đợi xoá lại).
    @discardableResult
    static func delete(bookId: String) -> Bool {
        guard !bookId.isEmpty else { return true }
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.shared.log("❌ [Annotations] Không xoá được ghi chú / dấu trang của truyện: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Sao lưu (theo tên file = hash của bookId; khôi phục cùng bookId ⇒ cùng hash)

    /// Mọi bản trên máy, khoá = tên file (hash). Bỏ file hỏng / file `.broken-…`.
    static func loadAllByHash() -> [String: BookAnnotations] {
        lock.lock()
        defer { lock.unlock() }
        let files = (try? FileManager.default.contentsOfDirectory(at: directoryURL, includingPropertiesForKeys: nil)) ?? []
        var result: [String: BookAnnotations] = [:]
        for url in files where url.pathExtension == "json" {
            let hash = url.deletingPathExtension().lastPathComponent
            guard isHash(hash), let data = try? Data(contentsOf: url),
                  let value = try? decode(BookAnnotations.self, from: data), !value.isEmpty else { continue }
            result[hash] = value
        }
        return result
    }

    /// Khôi phục: gộp từng bản vào file cùng hash (mục trên máy thắng). Trả số mục thêm mới.
    static func mergeRestored(_ byHash: [String: BookAnnotations]) -> Int {
        lock.lock()
        defer { lock.unlock() }
        var added = 0
        for (hash, incoming) in byHash where isHash(hash) {
            let url = directoryURL.appendingPathComponent("\(hash).json")
            let existing = (try? Data(contentsOf: url)).flatMap { try? decode(BookAnnotations.self, from: $0) } ?? BookAnnotations()
            let merged = existing.merging(incoming)
            let delta = (merged.bookmarks.count - existing.bookmarks.count) + (merged.notes.count - existing.notes.count)
            guard delta > 0 else { continue }
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                try encode(merged).write(to: url, options: .atomic)
                added += delta
            } catch {
                AppLogger.shared.log("❌ [Annotations] Không ghi được ghi chú / dấu trang khôi phục: \(error.localizedDescription)")
            }
        }
        return added
    }

    /// Tên file hợp lệ: 64 ký tự hex thường (`String.sha256()`).
    static func isHash(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    // MARK: - Mã hoá (dùng chung với sao lưu)

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: data)
    }

    // MARK: - Nội bộ (gọi khi đã giữ `lock`)

    private static func loadLocked(bookId: String) -> BookAnnotations {
        let url = fileURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return BookAnnotations() }
        do {
            return try decode(BookAnnotations.self, from: Data(contentsOf: url))
        } catch {
            AppLogger.shared.log("❌ [Annotations] File ghi chú / dấu trang hỏng, cất sang bản .broken: \(error.localizedDescription)")
            quarantine(url)
            return BookAnnotations()
        }
    }

    private static func saveLocked(_ annotations: BookAnnotations, bookId: String) {
        let url = fileURL(bookId: bookId)
        do {
            if annotations.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try encode(annotations).write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [Annotations] Không ghi được ghi chú / dấu trang: \(error.localizedDescription)")
        }
    }

    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }
}
