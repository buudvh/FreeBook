import Foundation
import Combine

/// In-memory cache for global (shared) dictionaries.
/// Loads custom entries from `.txt` files on first access, then keeps them in RAM.
/// CRUD operations update the unified custom/deleted `.txt` file atomically.
@MainActor
public final class DictionaryCache: ObservableObject {
    public static let shared = DictionaryCache()

    @Published public var vietPhraseEntries: [DictEntry]? = nil
    @Published public var namesEntries: [DictEntry]? = nil
    @Published public var isLoadingVP = false
    @Published public var isLoadingNames = false

    private init() {}

    // MARK: - Load

    public func loadIfNeeded(type: DictType) async {
        switch type {
        case .vietPhrase:
            guard vietPhraseEntries == nil, !isLoadingVP else { return }
            isLoadingVP = true
            let entries = await loadFromText(type: type)
            vietPhraseEntries = entries
            isLoadingVP = false
        case .names:
            guard namesEntries == nil, !isLoadingNames else { return }
            isLoadingNames = true
            let entries = await loadFromText(type: type)
            namesEntries = entries
            isLoadingNames = false
        }
    }

    private func loadFromText(type: DictType) async -> [DictEntry] {
        let translateDir = TranslationManager.shared.translateDirectory
        let fileUrl = Self.globalCustomTextURL(type: type, translateDir: translateDir)
        return await Task.detached(priority: .userInitiated) {
            let raw = DictionaryTextFileStore.loadEntries(from: fileUrl)
            return raw.map { DictEntry(key: $0.key, value: $0.value) }
        }.value
    }

    // MARK: - CRUD

    /// Upsert: if key exists, move & update value at index 0; if not, insert at index 0.
    public func upsertEntry(key: String, value: String, type: DictType) async throws {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = DictionaryTextFileStore.normalizeMeaning(value)
        guard !cleanKey.isEmpty, !cleanValue.isEmpty else { return }

        var records = currentRecords(for: type)
        records.removeAll { $0.key == cleanKey }
        records.insert(DictionaryTextRecord(key: cleanKey, value: cleanValue), at: 0)

        try await persistAndUpdate(records: records, type: type)
    }

    /// Update key: if newKey != oldKey, keep oldKey, upsert newKey at index 0.
    public func updateKey(oldKey: String, newKey: String, newValue: String, type: DictType) async throws {
        let cleanNewKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanValue = DictionaryTextFileStore.normalizeMeaning(newValue)
        guard !cleanNewKey.isEmpty, !cleanValue.isEmpty else { return }

        var records = currentRecords(for: type)
        if newKey == oldKey {
            records.removeAll { $0.key == oldKey }
        } else {
            records.removeAll { $0.key == cleanNewKey }
        }
        records.insert(DictionaryTextRecord(key: cleanNewKey, value: cleanValue), at: 0)

        try await persistAndUpdate(records: records, type: type)
    }

    public func deleteEntry(key: String, type: DictType) async throws {
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanKey.isEmpty else { return }

        var records = currentRecords(for: type)
        let before = records.count
        records.removeAll { $0.key == cleanKey }

        let isName = type == .names
        if TranslationManager.shared.existsInBaseDictionary(word: cleanKey, isName: isName) {
            records.insert(DictionaryTextRecord(key: cleanKey, value: ""), at: 0)
        }

        guard records.count != before || records.first?.key == cleanKey else { return }
        try await persistAndUpdate(records: records, type: type)
    }

    public func importEntries(from url: URL, type: DictType, isMerge: Bool = false) async throws {
        let importedRecords = try DictionaryTextFileStore.parseRecords(from: url)
        let importedKeys = Set(importedRecords.map { $0.key })
        let importedWithValue = Set(importedRecords.filter { !$0.isDeleted }.map { $0.key })

        let existingRecords = currentRecords(for: type)
        let existingCustom = existingRecords.filter { !$0.isDeleted }
        let existingDeleted = existingRecords.filter { $0.isDeleted }
        let existingDeletedKeys = Set(existingDeleted.map { $0.key })

        let records: [DictionaryTextRecord]
        if isMerge {
            // MERGE: giữ custom cũ không trùng key, import thắng key trùng,
            // bảo toàn deleted không bị restore, thêm deleted mới từ import.
            let mergedCustom = existingCustom.filter { !importedKeys.contains($0.key) }
            let importedCustom = importedRecords.filter { !$0.isDeleted }
            let preservedDeleted = existingDeleted.filter { !importedWithValue.contains($0.key) }
            let newDeletedFromImport = importedRecords.filter { $0.isDeleted && !existingDeletedKeys.contains($0.key) }
            records = mergedCustom + importedCustom + preservedDeleted + newDeletedFromImport
        } else {
            // REPLACE: xóa sạch dữ liệu cũ (custom + deleted), chỉ giữ file import.
            records = importedRecords
        }

        try await persistAndUpdate(records: records, type: type)
        invalidate(type: type)
        await loadIfNeeded(type: type)
    }

    public func invalidate(type: DictType) {
        switch type {
        case .vietPhrase: vietPhraseEntries = nil
        case .names: namesEntries = nil
        }
    }

    public func invalidateAll() {
        vietPhraseEntries = nil
        namesEntries = nil
    }
    
    public func clearAllEntries(type: DictType) async throws {
        let deletedRecords = currentRecords(for: type).filter { $0.isDeleted }
        try await persistAndUpdate(records: deletedRecords, type: type)
    }

    // MARK: - Helpers

    private static func globalCustomTextURL(type: DictType, translateDir: URL) -> URL {
        translateDir.appendingPathComponent("Custom\(type.fileName).txt")
    }

    private func currentRecords(for type: DictType) -> [DictionaryTextRecord] {
        let translateDir = TranslationManager.shared.translateDirectory
        let fileUrl = Self.globalCustomTextURL(type: type, translateDir: translateDir)
        return (try? DictionaryTextFileStore.parseRecords(from: fileUrl)) ?? []
    }

    private func persistAndUpdate(records: [DictionaryTextRecord], type: DictType) async throws {
        let translateDir = TranslationManager.shared.translateDirectory
        let fileUrl = Self.globalCustomTextURL(type: type, translateDir: translateDir)

        try await Task.detached(priority: .userInitiated) {
            try DictionaryTextFileStore.persist(records: records, to: fileUrl)
        }.value

        let entries = DictionaryTextFileStore.loadEntries(from: fileUrl)
            .map { DictEntry(key: $0.key, value: $0.value) }

        // Update in-memory cache
        switch type {
        case .vietPhrase: vietPhraseEntries = entries
        case .names: namesEntries = entries
        }

        // Reload translation engine
        try await TranslationManager.shared.loadAllDictionaries()
        TranslationManager.shared.notifyDictionariesDidUpdate(bookId: nil)
    }
}

// MARK: - Shared Types

public enum DictType: String {
    case vietPhrase
    case names

    var displayName: String {
        switch self {
        case .vietPhrase: return "VietPhrase"
        case .names: return "Names"
        }
    }

    var fileName: String {
        switch self {
        case .vietPhrase: return "VietPhrase"
        case .names: return "Names"
        }
    }
}

public struct DictEntry: Identifiable, Hashable {
    public var id: String { key }
    public let key: String
    public let value: String
}
