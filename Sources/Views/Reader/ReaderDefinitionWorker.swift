import Foundation

/// One serial CPU worker per Reader. Cache only the latest paragraph, not every selection.
actor ReaderDefinitionWorker {
    struct Request: Sendable, Equatable {
        let sentence: String
        let word: String
        let bookId: String
        let mode: String
        let convertTraditional: Bool
    }

    struct Result: Sendable {
        let generation: Int
        let meaning: String
        let tokens: [TranslationWordToken]
        let matches: [DictionaryMatchInfo]
        let suggestions: [SuggestionChip]
        let hasRules: Bool
        let rulesEnabled: Bool
    }

    struct Traces: Sendable {
        let generation: Int
        let values: [QuickTranslationRuleTrace]
    }

    private var tokenKey = ""
    private var cachedTokens: [TranslationWordToken] = []
    private var traceKey = ""
    private var cachedTraces: [QuickTranslationRuleTrace] = []

    func load(_ request: Request, includesDefinitionData: Bool = true) throws -> Result {
        try Task.checkCancellation()
        let context = TranslationReadContext.capture(bookId: request.bookId)
        return try TranslationReadContext.$current.withValue(context) {
            let key = "\(context.generation)|\(request.bookId)|\(request.sentence)"
            let tokens = key == tokenKey ? cachedTokens
                : TranslateUtils.getTranslationTokens(for: request.sentence, bookId: request.bookId)
            try Task.checkCancellation()
            let meaning: String
            let matches: [DictionaryMatchInfo]
            let suggestions: [SuggestionChip]
            if includesDefinitionData {
                meaning = request.mode == "VP"
                    ? TranslateUtils.translateTerm(request.word, bookId: request.bookId,
                        shouldConvertTraditionalToSimplified: request.convertTraditional)
                    : ReaderSelectionCoordinator.hanViet(for: request.word)
                matches = ReaderView.dictionaryMatches(for: request.word, bookId: request.bookId)
                suggestions = ReaderView.buildSuggestionChips(for: request.word, bookId: request.bookId)
            } else {
                meaning = ""
                matches = []
                suggestions = []
            }
            try Task.checkCancellation()
            if context.isCurrent { tokenKey = key; cachedTokens = tokens }
            return Result(generation: context.generation, meaning: meaning, tokens: tokens,
                matches: matches, suggestions: suggestions, hasRules: context.hasRules,
                rulesEnabled: context.rulesEnabled)
        }
    }

    func traces(sentence: String, bookId: String, selection: NSRange) throws -> Traces {
        try Task.checkCancellation()
        let context = TranslationReadContext.capture(bookId: bookId)
        let key = "\(context.generation)|\(bookId)|\(sentence)"
        let traces = key == traceKey ? cachedTraces : TranslationReadContext.$current.withValue(context) {
            QuickTranslationRuleDiagnostics.diagnose(text: sentence, bookId: bookId)
        }
        try Task.checkCancellation()
        if context.isCurrent { traceKey = key; cachedTraces = traces }
        return Traces(generation: context.generation, values: QuickTranslationRuleDiagnostics.selecting(selection, in: traces))
    }
}
