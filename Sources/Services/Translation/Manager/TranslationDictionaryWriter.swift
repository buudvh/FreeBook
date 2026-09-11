import Foundation

/// Serial read-modify-write transactions. Once accepted, saves outlive presentation cancellation.
actor TranslationDictionaryWriter {
    static let shared = TranslationDictionaryWriter()

    func importEntries(from url: URL, isName: Bool, bookId: String?, isMerge: Bool) throws {
        let imported = try DictionaryTextFileStore.parseRecords(from: url)
        try mutate(isName: isName, bookId: bookId) { existing in
            if bookId != nil {
                existing = DictionaryTextFileStore.mergedRecords(imported: imported, existing: existing, isMerge: isMerge)
            } else if isMerge {
                let keys = Set(imported.map(\.key))
                let restored = Set(imported.filter { !$0.isDeleted }.map(\.key))
                let oldDeleted = existing.filter(\.isDeleted)
                let oldDeletedKeys = Set(oldDeleted.map(\.key))
                existing = existing.filter { !$0.isDeleted && !keys.contains($0.key) }
                    + imported.filter { !$0.isDeleted }
                    + oldDeleted.filter { !restored.contains($0.key) }
                    + imported.filter { $0.isDeleted && !oldDeletedKeys.contains($0.key) }
            } else {
                existing = imported
            }
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
