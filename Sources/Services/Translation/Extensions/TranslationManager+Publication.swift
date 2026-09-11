import Foundation

extension TranslationManager {
    internal func publishCustomRecords(_ records: [DictionaryTextRecord], isName: Bool) {
        var entries: [String: String] = [:]
        for record in records where !record.isDeleted && entries[record.key] == nil {
            entries[record.key] = record.value
        }
        let frozen = entries.isEmpty ? nil : FrozenTrieDictionary(
            entries: entries, lengths: Set(entries.keys.map { $0.utf16.count }).sorted(by: >)
        )
        let deleted = records.filter(\.isDeleted).map(\.key)
        dictionaryState.update {
            if isName {
                $0.customNames = frozen
                $0.deletedNames = Set(deleted)
                $0.deletedNamesList = deleted
                $0.customNameRecords = records
            } else {
                $0.customVietPhrase = frozen
                $0.deletedVietPhrase = Set(deleted)
                $0.deletedVietPhraseList = deleted
                $0.customVPRecords = records
            }
        }
        Task { @MainActor in
            self.publishCustomUI(isName: isName)
            DictionaryCache.shared.refreshIfLoaded(type: isName ? .names : .vietPhrase)
        }
    }
}
