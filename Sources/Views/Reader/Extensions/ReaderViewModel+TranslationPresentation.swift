import Foundation

extension ReaderViewModel {
    func chapterTitle(at index: Int) -> String {
        if let cached = cache.cache[index], !cached.title.isEmpty { return cached.title }
        if onlineChapters.indices.contains(index) { return onlineChapters[index].name }
        return "Chương \(index + 1)"
    }

    func originalChapterTitle(at index: Int) -> String? {
        if let cached = cache.cache[index], !cached.originalTitle.isEmpty { return cached.originalTitle }
        if onlineChapters.indices.contains(index) {
            let title = onlineChapters[index].name
            return title.isEmpty ? nil : title
        }
        return nil
    }

    func cancelObsoleteTranslationRefresh() {
        translationRefreshTask?.cancel()
        translationPresentation.pending = nil
    }

    func setTranslationRefreshDeferred(_ deferred: Bool) {
        translationPresentation.deferred = deferred
        guard !deferred, let pending = translationPresentation.pending else { return }
        translationPresentation.pending = nil
        guard pending.index == displayedChapterIndex,
              pending.revision == currentRevision,
              pending.token == TranslateUtils.translationGenerationToken(for: bookId),
              pending.translationEnabled == isTranslationEnabled,
              pending.convertTraditional == shouldConvertTraditionalToSimplified else { return }
        applyPreparedTranslation(pending)
    }

    internal func applyPreparedTranslation(_ prepared: ReaderTranslationPresentation.Prepared) {
        let cached = cache.cache[prepared.index] ?? cache.setPlaceholder(prepared.index)
        let result = prepared.result
        let equal = cached.originalTitle == prepared.originalTitle &&
            cached.originalContent == prepared.originalContent &&
            cached.title == result.translatedTitle && cached.content == result.translatedContent &&
            cached.paragraphItems == result.paragraphItems &&
            cached.isTranslationEnabled == prepared.translationEnabled &&
            cached.shouldConvertTraditionalToSimplified == prepared.convertTraditional && cached.state == .loaded
        if !equal {
            cached.originalTitle = prepared.originalTitle
            cached.originalContent = prepared.originalContent
            cached.title = result.translatedTitle
            cached.content = result.translatedContent
            cached.paragraphItems = result.paragraphItems
            cached.isTranslationEnabled = prepared.translationEnabled
            cached.shouldConvertTraditionalToSimplified = prepared.convertTraditional
            cached.state = .loaded
        }
        cached.revision = prepared.revision
        cached.translationToken = prepared.token
    }
}
