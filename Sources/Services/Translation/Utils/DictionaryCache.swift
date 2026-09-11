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
        case .names:
            guard namesEntries == nil, !isLoadingNames else { return }
        }
        refreshFromPublishedState(type: type)
    }

    internal func refreshIfLoaded(type: DictType) {
        guard (type == .names ? namesEntries : vietPhraseEntries) != nil else { return }
        refreshFromPublishedState(type: type)
    }

    // MARK: - CRUD

    /// Upsert: if key exists, move & update value at index 0; if not, insert at index 0.
    public func upsertEntry(key: String, value: String, type: DictType) async throws {
        try await TranslationManager.shared.saveCustomEntry(word: key, meaning: value, isName: type == .names, bookId: nil)
        refreshFromPublishedState(type: type)
    }

    /// Update key: if newKey != oldKey, keep oldKey, upsert newKey at index 0.
    public func updateKey(oldKey: String, newKey: String, newValue: String, type: DictType) async throws {
        try await upsertEntry(key: newKey, value: newValue, type: type)
    }

    public func deleteEntry(key: String, type: DictType) async throws {
        try await TranslationManager.shared.deleteCustomEntry(word: key, isName: type == .names, bookId: nil)
        refreshFromPublishedState(type: type)
    }

    public func importEntries(from url: URL, type: DictType, isMerge: Bool = false) async throws {
        try await TranslationDictionaryWriter.shared.importEntries(from: url, isName: type == .names, bookId: nil, isMerge: isMerge)
        refreshFromPublishedState(type: type)
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
        try await TranslationDictionaryWriter.shared.mutate(isName: type == .names, bookId: nil) {
            $0.removeAll { !$0.isDeleted }
        }
        refreshFromPublishedState(type: type)
    }

    // MARK: - Helpers

    internal func refreshFromPublishedState(type: DictType) {
        let state = TranslationManager.shared.dictionaryState.read()
        let records = type == .names ? state.customNameRecords : state.customVPRecords
        let entries = records.filter { !$0.isDeleted }.map { DictEntry(key: $0.key, value: $0.value) }
        switch type {
        case .vietPhrase: vietPhraseEntries = entries
        case .names: namesEntries = entries
        }
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
