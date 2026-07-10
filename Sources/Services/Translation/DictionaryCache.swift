import Foundation
import Combine

/// In-memory cache for global (shared) dictionaries.
/// Loads entries from `.dat` files on first access, then keeps them in RAM.
/// CRUD operations update both the cache and the `.dat` file atomically.
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
            let entries = await loadFromDat(fileName: "VietPhrase.dat")
            vietPhraseEntries = entries
            isLoadingVP = false
        case .names:
            guard namesEntries == nil, !isLoadingNames else { return }
            isLoadingNames = true
            let entries = await loadFromDat(fileName: "Names.dat")
            namesEntries = entries
            isLoadingNames = false
        }
    }

    private func loadFromDat(fileName: String) async -> [DictEntry] {
        let fileUrl = TranslationManager.shared.translateDirectory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileUrl.path) else { return [] }

        let dat = DoubleArrayTrie()
        try? dat.load(from: fileUrl)
        guard dat.isLoaded else { return [] }

        let raw = dat.allEntries()
        return raw.map { DictEntry(key: $0.key, value: $0.value) }
            .sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
    }

    // MARK: - CRUD

    /// Upsert: if key exists, update value; if not, insert new entry.
    public func upsertEntry(key: String, value: String, type: DictType) async throws {
        var entries = currentEntries(for: type)

        if let idx = entries.firstIndex(where: { $0.key == key }) {
            entries[idx] = DictEntry(key: key, value: value)
        } else {
            entries.append(DictEntry(key: key, value: value))
            entries.sort { $0.key.localizedCompare($1.key) == .orderedAscending }
        }

        try await persistAndUpdate(entries: entries, type: type)
    }

    /// Update key: remove old key, insert with new key (upsert semantics).
    public func updateKey(oldKey: String, newKey: String, newValue: String, type: DictType) async throws {
        var entries = currentEntries(for: type)

        // Remove old entry
        entries.removeAll { $0.key == oldKey }

        // Upsert new key
        if let idx = entries.firstIndex(where: { $0.key == newKey }) {
            entries[idx] = DictEntry(key: newKey, value: newValue)
        } else {
            entries.append(DictEntry(key: newKey, value: newValue))
            entries.sort { $0.key.localizedCompare($1.key) == .orderedAscending }
        }

        try await persistAndUpdate(entries: entries, type: type)
    }

    public func deleteEntry(key: String, type: DictType) async throws {
        var entries = currentEntries(for: type)
        let before = entries.count
        entries.removeAll { $0.key == key }
        guard entries.count < before else { return }

        try await persistAndUpdate(entries: entries, type: type)
    }

    public func importEntries(from url: URL, type: DictType) async throws {
        let fileName = type == .vietPhrase ? "VietPhrase.dat" : "Names.dat"
        let datUrl = TranslationManager.shared.translateDirectory.appendingPathComponent(fileName)

        try DoubleArrayTrieBuilder().build(fromTxtFile: url, toDatFile: datUrl)

        // Reload cache
        invalidate(type: type)
        TranslateUtils.clearCache()
        try await TranslationManager.shared.loadAllDictionaries()
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

    // MARK: - Helpers

    private func currentEntries(for type: DictType) -> [DictEntry] {
        switch type {
        case .vietPhrase: return vietPhraseEntries ?? []
        case .names: return namesEntries ?? []
        }
    }

    private func persistAndUpdate(entries: [DictEntry], type: DictType) async throws {
        let fileName = type == .vietPhrase ? "VietPhrase.dat" : "Names.dat"
        let datUrl = TranslationManager.shared.translateDirectory.appendingPathComponent(fileName)

        let raw = entries.map { (key: $0.key, value: $0.value) }

        if raw.isEmpty {
            try? FileManager.default.removeItem(at: datUrl)
        } else {
            try DoubleArrayTrieBuilder().build(fromEntries: raw, toDatFile: datUrl)
        }

        // Update in-memory cache
        switch type {
        case .vietPhrase: vietPhraseEntries = entries
        case .names: namesEntries = entries
        }

        // Reload translation engine
        TranslateUtils.clearCache()
        try await TranslationManager.shared.loadAllDictionaries()
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
