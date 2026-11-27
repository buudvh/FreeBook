import Foundation

/// Engine lưu trữ mức thấp — chủ **duy nhất** của thư mục `applicationSupportDirectory/name_filter_drafts/` (gói name tạm
/// của "Lọc name local", plan 2026-11-27 mục E2): mỗi truyện một file `<sha256(bookId)>.json` = các `LocalNameFilterDraft`,
/// ghi gần nhất trước, tối đa `maxDraftsPerBook` gói (quá thì bỏ gói ghi lâu nhất). Không giữ trạng thái; đọc / ghi đồng
/// bộ, gọi được từ luồng bất kỳ (tuần tự qua `lock`). Màn hình gọi thẳng (không có SwiftData, không cần coordinator).
///
/// Đi theo truyện: đổi nguồn (`BookSourceMigrator` chép / xoá), Dung lượng (`StorageUsageCategory.nameFilterDrafts`),
/// Dọn rác (file của truyện không còn trong thư viện, `JunkScanner.deletedBookCandidates`). Sao lưu **không** gói (dữ liệu
/// tạm). Ghi `.atomic`; hết gói ⇒ xoá file. File đọc lỗi ⇒ đổi tên sang `.broken-<thời điểm>.json` rồi coi như rỗng.
enum LocalNameFilterDraftStore {
    static let directoryName = "name_filter_drafts"
    static let maxDraftsPerBook = 5

    /// Nội dung một file (có `version` để đổi định dạng sau này).
    private struct FileContent: Codable {
        var version: Int = 1
        var drafts: [LocalNameFilterDraft]
    }

    private static let lock = NSLock()

    static var directoryURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Tên file = SHA-256 hex của `bookId` (`String.sha256()`, cùng hàm băm của `BookAnnotationStore` / `JunkScanner`).
    static func fileURL(bookId: String) -> URL {
        directoryURL.appendingPathComponent("\(bookId.sha256()).json")
    }

    // MARK: - Đọc / ghi

    /// Gói của truyện, ghi gần nhất trước.
    static func load(bookId: String) -> [LocalNameFilterDraft] {
        guard !bookId.isEmpty else { return [] }
        lock.lock()
        defer { lock.unlock() }
        return loadLocked(bookId: bookId)
    }

    /// Ghi một gói: cùng `id` ⇒ thay gói cũ (mở lại rồi đóng chưa Lưu), chưa có ⇒ thêm. Gói rỗng ⇒ xoá gói cùng `id`.
    static func upsert(_ draft: LocalNameFilterDraft, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        var drafts = loadLocked(bookId: bookId).filter { $0.id != draft.id }
        if !draft.names.isEmpty {
            drafts.append(draft)
        }
        saveLocked(drafts, bookId: bookId)
    }

    /// Xoá một gói (lưu xong / vuốt Xoá). Không có gói đó ⇒ không ghi gì.
    static func delete(id: UUID, bookId: String) {
        guard !bookId.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        let drafts = loadLocked(bookId: bookId)
        guard drafts.contains(where: { $0.id == id }) else { return }
        saveLocked(drafts.filter { $0.id != id }, bookId: bookId)
    }

    /// Đổi nguồn: gộp gói của truyện cũ vào truyện đích (trùng `id` ⇒ giữ của đích), rồi giữ 5 gói ghi gần nhất. Không xoá
    /// bản cũ; chạy lại nhiều lần cho cùng kết quả.
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
        AppLogger.shared.log("🔎 [LọcName] Chép \(merged.count - target.count) gói name tạm sang truyện mới")
    }

    /// Xoá mọi gói của một truyện (đổi nguồn xong / lùi lại). Trả `false` khi file còn mà xoá lỗi.
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
            AppLogger.shared.log("❌ [LọcName] Không xoá được gói name tạm của truyện: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: - Nội bộ (gọi khi đã giữ `lock`)

    private static func loadLocked(bookId: String) -> [LocalNameFilterDraft] {
        let url = fileURL(bookId: bookId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let content = try decoder.decode(FileContent.self, from: Data(contentsOf: url))
            return content.drafts.sorted { $0.savedAt > $1.savedAt }
        } catch {
            AppLogger.shared.log("❌ [LọcName] File gói name tạm hỏng, cất sang bản .broken: \(error.localizedDescription)")
            quarantine(url)
            return []
        }
    }

    /// Ghi gần nhất trước, cắt còn `maxDraftsPerBook` (bỏ gói ghi lâu nhất). Rỗng ⇒ xoá file.
    private static func saveLocked(_ drafts: [LocalNameFilterDraft], bookId: String) {
        let url = fileURL(bookId: bookId)
        let sorted = drafts.sorted { $0.savedAt > $1.savedAt }
        let kept = Array(sorted.prefix(maxDraftsPerBook))
        if kept.count < sorted.count {
            AppLogger.shared.log("🔎 [LọcName] Quá \(maxDraftsPerBook) gói name tạm, bỏ \(sorted.count - kept.count) gói cũ nhất")
        }
        do {
            if kept.isEmpty {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                return
            }
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(FileContent(drafts: kept)).write(to: url, options: .atomic)
        } catch {
            AppLogger.shared.log("❌ [LọcName] Không ghi được gói name tạm: \(error.localizedDescription)")
        }
    }

    private static func quarantine(_ url: URL) {
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingPathExtension().appendingPathExtension("broken-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: target)
    }

    /// Bản `.broken-…` đã cất của một truyện (`<hash>.broken-<thời điểm>.json`): xoá theo truyện. Dọn rác cố ý bỏ qua các
    /// file này (tên không phải 64 ký tự hex), nên đây là lối dọn duy nhất.
    private static func removeQuarantined(of url: URL) {
        let prefix = url.deletingPathExtension().lastPathComponent + ".broken-"
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directoryURL.path)) ?? []
        for name in names where name.hasPrefix(prefix) && name.hasSuffix(".json") {
            try? FileManager.default.removeItem(at: directoryURL.appendingPathComponent(name))
        }
    }
}
