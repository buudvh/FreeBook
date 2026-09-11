import Foundation

/// A synchronous translation pass uses one immutable dictionary/rule/configuration snapshot.
struct TranslationReadContext: Sendable {
    @TaskLocal static var current: TranslationReadContext?

    let bookId: String?
    let generation: Int
    let dictionaryRevision: UInt64
    let dictionaries: TranslationDictionaryState.Global
    let bookDictionaries: TranslationDictionaryState.Book
    let pronounsEnabled: Bool
    let luatNhanEnabled: Bool
    let rulesEnabled: Bool
    let globalRules: QuickTranslationRuleSnapshot?
    let bookRules: QuickTranslationRuleSnapshot?
    let disabledRules: QuickTranslationRuleDisableStore.Snapshot
    let tokens: QuickTranslationRuleTokenSettings.Configuration
    let priority: QuickTranslationRulePriorityConfiguration.Configuration

    var isCurrent: Bool {
        generation == TranslateUtils.translationGenerationToken(for: bookId)
            && dictionaryRevision == TranslationManager.shared.dictionaryState.revision()
    }
    var hasRules: Bool { globalRules != nil || bookRules != nil }

    static func capture(bookId: String?) -> Self {
        while true {
            let manager = TranslationManager.shared
            let generation = TranslateUtils.translationGenerationToken(for: bookId)
            let dictionarySnapshot = manager.dictionaryState.snapshot()
            let book = bookId.map {
                manager.dictionaryState.book($0, directory: manager.translateDirectory.appendingPathComponent("books").appendingPathComponent($0))
            } ?? .init(vietPhrase: nil, names: nil)
            let context = Self(
                bookId: bookId, generation: generation,
                dictionaryRevision: dictionarySnapshot.revision, dictionaries: dictionarySnapshot.global,
                bookDictionaries: book,
                pronounsEnabled: UserDefaults.standard.bool(forKey: "isTranslationPronounsEnabled"),
                luatNhanEnabled: UserDefaults.standard.bool(forKey: "isTranslationLuatNhanEnabled"),
                rulesEnabled: QuickTranslationRuleStore.shared.isEnabled,
                globalRules: QuickTranslationRuleStore.shared.currentSnapshot,
                bookRules: QuickTranslationRuleBookStore.shared.snapshot(for: bookId),
                disabledRules: QuickTranslationRuleDisableStore.shared.snapshot(bookId: bookId),
                tokens: QuickTranslationBookEngineConfigStore.shared.tokenConfiguration(bookId: bookId),
                priority: QuickTranslationBookEngineConfigStore.shared.priorityConfiguration(bookId: bookId)
            )
            if context.isCurrent { return context }
        }
    }

    static func withSnapshot<T>(bookId: String?, _ operation: () throws -> T) rethrows -> T {
        if let current, current.bookId == bookId { return try operation() }
        return try $current.withValue(capture(bookId: bookId), operation: operation)
    }

    static func cacheGeneration(for bookId: String?) -> Int {
        if let current, current.bookId == bookId { return current.generation }
        return TranslateUtils.translationGenerationToken(for: bookId)
    }
}
