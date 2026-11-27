import Foundation

/// Serial read-modify-write transactions. Once accepted, saves outlive presentation cancellation.
actor TranslationDictionaryWriter {
    static let shared = TranslationDictionaryWriter()

    /// Số liệu cho toast "thêm X, cập nhật Y" của chỗ nhập. `updated` = khoá đã có mà nghĩa đổi (chỉ chế độ "Gộp").
    struct ImportCounts: Sendable {
        let added: Int
        let updated: Int
    }

    /// Nhập file `từ=nghĩa` vào lớp custom (Chung, `bookId == nil`) hoặc từ điển riêng của truyện, theo `DataImportMode`:
    /// - `.replaceAll`: chỉ giữ nội dung file.
    /// - `.overwriteExisting` ("Gộp"): trùng khoá lấy nghĩa **mới**; khoá mới thêm; khoá chỉ có trên máy giữ.
    /// - `.keepExisting` ("Chỉ thêm key mới"): chỉ thêm khoá chưa có; khoá đã có giữ nghĩa cũ.
    ///
    /// Lớp Chung có mục đã xoá (tombstone `từ=`): "Gộp" giữ luật cũ (mục sống của file khôi phục từ đã xoá, tombstone
    /// của file thêm vào danh sách đã xoá); "Chỉ thêm key mới" coi tombstone như một khoá đã có — từ đã xoá trên máy vẫn
    /// xoá dù file có nghĩa, tombstone của file chỉ thêm khi máy chưa có khoá đó.
    @discardableResult
    func importEntries(from url: URL, isName: Bool, bookId: String?, mode: DataImportMode) throws -> ImportCounts {
        let imported = try DictionaryTextFileStore.parseRecords(from: url)
        return try importRecords(imported, isName: isName, bookId: bookId, mode: mode)
    }

    /// Như `importEntries(from:)` nhưng nhận sẵn bản ghi (nghĩa đã qua `DictionaryTextFileStore.normalizeMeaning`, khoá
    /// không lặp): nút Lưu của màn duyệt name AI / Lọc name local (`AIHarnessService.saveExtractedEntries`, plan
    /// 2026-11-27-phan-loai-name L16) — cùng một luật ba chế độ với nhập file.
    @discardableResult
    func importRecords(
        _ imported: [DictionaryTextRecord], isName: Bool, bookId: String?, mode: DataImportMode
    ) throws -> ImportCounts {
        // Đọc trước để đếm (closure của `mutate` là `@Sendable`, không ghi được biến ngoài). Actor ⇒ không lượt ghi nào
        // chen giữa hai lần đọc vì không có `await` ở giữa.
        let fileURL = TranslationManager.shared.customTextURL(isName: isName, bookId: bookId)
        let existing = FileManager.default.fileExists(atPath: fileURL.path)
            ? try DictionaryTextFileStore.parseRecords(from: fileURL) : []
        let result = Self.merged(imported: imported, existing: existing, isGlobal: bookId == nil, mode: mode)
        let records = result.records
        try mutate(isName: isName, bookId: bookId) { $0 = records }
        return result.counts
    }

    private static func merged(
        imported: [DictionaryTextRecord],
        existing: [DictionaryTextRecord],
        isGlobal: Bool,
        mode: DataImportMode
    ) -> (records: [DictionaryTextRecord], counts: ImportCounts) {
        let existingValues = Dictionary(existing.map { ($0.key, $0.value) }, uniquingKeysWith: { first, _ in first })
        let fresh = imported.filter { existingValues[$0.key] == nil }
        switch mode {
        case .replaceAll:
            return (imported, ImportCounts(added: imported.count, updated: 0))
        case .overwriteExisting:
            let updated = imported.filter { record in
                existingValues[record.key].map { $0 != record.value } ?? false
            }.count
            let counts = ImportCounts(added: fresh.count, updated: updated)
            guard isGlobal else {
                return (DictionaryTextFileStore.mergedRecords(imported: imported, existing: existing, isMerge: true), counts)
            }
            let keys = Set(imported.map(\.key))
            let restored = Set(imported.filter { !$0.isDeleted }.map(\.key))
            let oldDeleted = existing.filter(\.isDeleted)
            let oldDeletedKeys = Set(oldDeleted.map(\.key))
            let records = existing.filter { !$0.isDeleted && !keys.contains($0.key) }
                + imported.filter { !$0.isDeleted }
                + oldDeleted.filter { !restored.contains($0.key) }
                + imported.filter { $0.isDeleted && !oldDeletedKeys.contains($0.key) }
            return (records, counts)
        case .keepExisting:
            let counts = ImportCounts(added: fresh.count, updated: 0)
            // Riêng truyện: như "Gộp" của truyện, mục mới lên đầu, mục cũ giữ nguyên thứ tự.
            guard isGlobal else { return (fresh + existing, counts) }
            let records = existing.filter { !$0.isDeleted } + fresh.filter { !$0.isDeleted }
                + existing.filter(\.isDeleted) + fresh.filter(\.isDeleted)
            return (records, counts)
        }
    }

    func mutate(
        isName: Bool, bookId: String?, scope: DictionaryInvalidationScope = .globalReload,
        change: @Sendable (inout [DictionaryTextRecord]) throws -> Void
    ) throws {
        let manager = TranslationManager.shared
        let url = manager.customTextURL(isName: isName, bookId: bookId)
        var records: [DictionaryTextRecord] = []
        if FileManager.default.fileExists(atPath: url.path) {
            records = try DictionaryTextFileStore.parseRecords(from: url)
        }
        try change(&records)
        try DictionaryTextFileStore.persist(records: records, to: url)
        if let bookId {
            manager.clearBookDictCache(for: bookId)
        } else {
            manager.publishCustomRecords(records, isName: isName)
        }
        manager.notifyDictionariesDidUpdate(bookId: bookId, scope: scope)
    }
}
