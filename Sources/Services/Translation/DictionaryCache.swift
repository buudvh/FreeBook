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
        let translateDir = TranslationManager.shared.translateDirectory
        return await Task.detached(priority: .userInitiated) {
            let customName = "Custom" + fileName
            let fileUrl = translateDir.appendingPathComponent(customName)
            guard FileManager.default.fileExists(atPath: fileUrl.path) else { return [] }

            let dat = DoubleArrayTrie()
            try? dat.load(from: fileUrl)
            guard dat.isLoaded else { return [] }

            let raw = dat.allEntries()
            return raw.map { DictEntry(key: $0.key, value: $0.value) }
                .sorted { $0.key.localizedCompare($1.key) == .orderedAscending }
        }.value
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

    /// Update key: if newKey != oldKey, keep oldKey, upsert newKey.
    public func updateKey(oldKey: String, newKey: String, newValue: String, type: DictType) async throws {
        var entries = currentEntries(for: type)

        if newKey != oldKey {
            // Keep oldKey (do not remove it), just upsert newKey with newValue
            if let idx = entries.firstIndex(where: { $0.key == newKey }) {
                entries[idx] = DictEntry(key: newKey, value: newValue)
            } else {
                entries.append(DictEntry(key: newKey, value: newValue))
                entries.sort { $0.key.localizedCompare($1.key) == .orderedAscending }
            }
        } else {
            // Just update the value of oldKey
            if let idx = entries.firstIndex(where: { $0.key == oldKey }) {
                entries[idx] = DictEntry(key: oldKey, value: newValue)
            }
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
        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.components(separatedBy: .newlines)
        
        var newCustomEntries: [DictEntry] = []
        var newlyDeleted: Set<String> = []
        
        for line in lines {
            let parts = line.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                let k = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                let v = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    if v.isEmpty {
                        newlyDeleted.insert(k)
                    } else {
                        newCustomEntries.append(DictEntry(key: k, value: v))
                    }
                }
            } else if parts.count == 1, line.contains("=") {
                let k = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty {
                    newlyDeleted.insert(k)
                }
            }
        }
        
        // Save custom entries
        try await persistAndUpdate(entries: newCustomEntries, type: type)
        
        // Save deleted list
        let isName = type == .names
        if !newlyDeleted.isEmpty {
            TranslationManager.shared.addDeletedWords(newlyDeleted, isName: isName)
        }
        let customKeys = newCustomEntries.map { $0.key }
        if !customKeys.isEmpty {
            TranslationManager.shared.removeDeletedWords(customKeys, isName: isName)
        }

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
    
    public func clearAllEntries(type: DictType) async throws {
        try await persistAndUpdate(entries: [], type: type)
    }

    // MARK: - Helpers

    private func currentEntries(for type: DictType) -> [DictEntry] {
        switch type {
        case .vietPhrase: return vietPhraseEntries ?? []
        case .names: return namesEntries ?? []
        }
    }

    private func persistAndUpdate(entries: [DictEntry], type: DictType) async throws {
        let fileName = type == .vietPhrase ? "CustomVietPhrase.dat" : "CustomNames.dat"
        let translateDir = TranslationManager.shared.translateDirectory
        let datUrl = translateDir.appendingPathComponent(fileName)

        let raw = entries.map { (key: $0.key, value: $0.value) }

        try await Task.detached(priority: .userInitiated) {
            if raw.isEmpty {
                try? FileManager.default.removeItem(at: datUrl)
            } else {
                try DoubleArrayTrieBuilder().build(fromEntries: raw, toDatFile: datUrl)
            }
        }.value

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
