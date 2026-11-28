import Foundation

/// Engine lưu trữ mức thấp — chủ **duy nhất** của thư mục `applicationSupportDirectory/name_filter_history/` ("Lịch sử lọc"
/// của Lọc name local, mockup + plan "Lịch sử lọc — H1–H5" https://claude.ai/artifact/JwiiU3XFYTk7Rz1hAMS7G2): mỗi truyện một
/// file `<sha256(bookId)>.json` = các `LocalNameFilterHistoryEntry`, **không giới hạn** số mục, đọc ra mới nhất trước (theo
/// giờ bắt đầu). Không giữ trạng thái; đọc / ghi đồng bộ, gọi được từ luồng bất kỳ (tuần tự qua `lock`). Màn hình gọi thẳng
/// (không có SwiftData, không cần coordinator).
///
/// Đi theo truyện như gói tạm (`LocalNameFilterDraftStore`): đổi nguồn (`BookSourceMigrator` chép / xoá), xoá truyện
/// (`BookStorageManager.deleteBookSideData`), Dung lượng (chung hàng `StorageUsageCategory.nameFilterDrafts`), Dọn rác (file
/// của truyện không còn trong thư viện, `JunkScanner.deletedBookCandidates`). Sao lưu **không** gói. Ghi `.atomic`; hết mục
/// ⇒ xoá file. File đọc lỗi ⇒ đổi tên sang `.broken-<thời điểm>.json` rồi coi như rỗng (lần mở sau gói tạm còn lại được tạo
/// mục lại — `LocalNameFilterHistoryStore+Drafts`).
enum LocalNameFilterHistoryStore {
    static let directoryName = "name_filter_history"

    /// Nội dung một file (có `version` để đổi định dạng sau này).
    private struct FileContent: Codable {
        var version: Int = 1
        var entries: [LocalNameFilterHistoryEntry]
    }

    private static let lock = NSLock()

    static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Tên file = SHA-256 hex của `bookId` (cùng hàm băm của gói tạm / `BookAnnotationStore` / `JunkScanner`).
    static func fileURL(bookId: String) -> URL {
        directoryURL.appendingPathComponent("\(bookId.sha256()).json")
    }

    // MARK: - Đọc / ghi

    /// Mục của truyện, mới nhất trước.
    static func load(bookId: String) -> [LocalNameFilterHistoryEntry] {
        guard !bookId.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(bookId: bookId)
    }

    /// Ghi một mục: cùng `id` ⇒ thay mục cũ, chưa có ⇒ thêm.
    static func record(_ entry: LocalNameFilterHistoryEntry, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = loadLocked(bookId: bookId).filter { $0.id != entry.id }
        entries.append(entry)
        saveLocked(entries, bookId: bookId)
    }

    /// Sửa mục `id` trong một lần giữ khoá (lượt lọc lấy xong danh sách chương / kết thúc — `LocalNameFilterSession+History`).
    /// Không có mục đó ⇒ không ghi gì. `transform` không được gọi hàm khác của store (khoá không lồng được).
    static func update(id: UUID, bookId: String, _ transform: (inout LocalNameFilterHistoryEntry) -> Void) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = loadLocked(bookId: bookId)
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = entries[index]
        transform(&entries[index])
        guard entries[index] != before else { return }
        saveLocked(entries, bookId: bookId)
    }

    /// Lưu xong màn duyệt của lượt `id`: ghi số name thực lưu + lúc lưu. Không có mục đó (ghi mục lỗi lúc lọc xong) ⇒ dựng
    /// mục từ `fallback` (gói của màn duyệt) rồi đánh dấu, để lần lọc này vẫn có trong lịch sử.
    static func markSaved(
        id: UUID,
        savedCount: Int,
        at date: Date,
        fallback: LocalNameFilterDraft?,
        bookId: String
    ) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var entries = loadLocked(bookId: bookId)
        if let index = entries.firstIndex(where: { $0.id == id }) {
            entries[index].savedCount = savedCount
            entries[index].savedAt = date
        } else if let fallback {
            var entry = LocalNameFilterHistoryEntry(draft: fallback)
            entry.savedCount = savedCount
            entry.savedAt = date
            entries.append(entry)
        } else {
            return
        }
        saveLocked(entries, bookId: bookId)
    }

    /// Thêm mục "chưa lưu" cho các gói tạm chưa có mục nào trỏ tới (`LocalNameFilterHistoryEntry(draft:)`). Tra theo `id`
    /// nên gọi lại bao nhiêu lần cũng không tạo trùng. Trả danh sách sau cùng, mới nhất trước.
    static func ensureEntries(for drafts: [LocalNameFilterDraft], bookId: String) -> [LocalNameFilterHistoryEntry] {
        guard !bookId.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        let entries = loadLocked(bookId: bookId)
        let known = Set(entries.map(\.id))
        let missing = drafts.filter { !known.contains($0.id) }
        guard !missing.isEmpty else { return entries }
        let merged = entries + missing.map { LocalNameFilterHistoryEntry(draft: $0) }
        saveLocked(merged, bookId: bookId)
        AppLogger.shared.log("🔎 [LọcName] Lịch sử lọc: tạo \(missing.count) mục chưa lưu cho gói tạm có sẵn")
        return newestFirst(merged)
    }

    /// Xoá các mục (vuốt Xoá, chọn nhiều, Dọn dẹp tất cả). Không có mục nào trong số đó ⇒ không ghi gì.
    static func delete(ids: Set<UUID>, bookId: String) {
        guard !bookId.isEmpty, !ids.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let entries = loadLocked(bookId: bookId)
        let kept = entries.filter { !ids.contains($0.id) }
        guard kept.count != entries.count else { return }
        saveLocked(kept, bookId: bookId)
    }

    /// Đổi nguồn: gộp mục của truyện cũ vào truyện đích (trùng `id` ⇒ giữ của đích). Không xoá bản cũ; chạy lại nhiều lần
    /// cho cùng kết quả.
    static func copy(from oldBookId: String, to newBookId: String) {
        guard !oldBookId.isEmpty, !newBookId.isEmpty, oldBookId != newBookId else { return }
        lock.lock()
        defer { lock.unlock() }
        let source = loadLocked(bookId: oldBookId)
        guard !source.isEmpty else { return }
        let target = loadLocked(bookId: newBookId)
        let targetIds = Set(target.map(\.id))
        let merged = target + source.filter { !targetIds.contains($0.id) }
        guard merged.count != target.count else { return }
        saveLocked(merged, bookId: newBookId)
        AppLogger.shared.log("🔎 [LọcName] Chép \(merged.count - target.count) mục lịch sử lọc sang truyện mới")
    }

    /// Xoá cả lịch sử của một truyện (xoá truyện, đổi nguồn xong / lùi lại). Trả `false` khi file còn mà xoá lỗi.
    @discardableResult
    static func deleteAll(bookId: String) -> Bool {
        guard !bookId.isEmpty else { return true }
        lock.lock()
        defer { lock.unlock() }
        let url = fileURL(bookId: bookId)
        removeQuarantined(of: url)
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        do {
            try FileManager.default.removeItem(at: url)
            return true
        } catch {
            AppLogger.shared.log("❌ [LọcName] Không xoá được lịch sử lọc của truyện: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Nội bộ (gọi khi đã giữ `lock`)

    /// Mới nhất trước; cùng giờ ⇒ giữ thứ tự ổn định theo `id`.
    private static func newestFirst(_ entries: [LocalNameFilterHistoryEntry]) -> [LocalNameFilterHistoryEntry] {
        entries.sorted {
            $0.startedAt != $1.startedAt ? $0.startedAt > $1.startedAt : $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func loadLocked(bookId: String) -> [LocalNameFilterHistoryEntry] {
        let url = fileURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let content = try decoder.decode(FileContent.self, from: Data(contentsOf: url))
            return newestFirst(content.entries)
        } catch {
            AppLogger.shared.log("❌ [LọcName] File lịch sử lọc hỏng, cất sang bản .broken: \(error.localizedDescription)")
            quarantine(url)
            return []
        }
    }

    /// Mới nhất trước. Rỗng ⇒ xoá file.
    private static func saveLocked(_ entries: [LocalNameFilterHistoryEntry], bookId: String) {
        let url = fileURL(bookId: bookId)
        do {
            if entries.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(FileContent(entries: newestFirst(entries))).write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [LọcName] Không ghi được lịch sử lọc: \(error.localizedDescription)")
        }
    }

    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }

    /// Bản `.broken-…` đã cất của một truyện: xoá theo truyện. Dọn rác cố ý bỏ qua các file này (tên không phải 64 ký tự
    /// hex), nên đây là lối dọn duy nhất.
    private static func removeQuarantined(of url: URL) {
        let prefix = url.deletingPathExtension().lastPathComponent + ".broken-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(name))
        }
    }
}
