import Foundation
import UIKit

extension ReaderViewModel {
    internal nonisolated func performChapterTranslationOffMainActor(
        originalTitle: String,
        originalContent: String,
        isTranslationEnabled: Bool,
        showTitle: Bool,
        bookId: String
    ) async throws -> (normalizedContent: String, buildResult: ReaderParagraphBuildResult) {
        try Task.checkCancellation()
        let normalizedText = ChapterTextNormalizer.normalize(originalContent)
        try Task.checkCancellation()
        let buildResult = try await buildCancellable(
            originalTitle: originalTitle,
            normalizedText: normalizedText,
            isTranslationEnabled: isTranslationEnabled,
            showTitle: showTitle,
            bookId: bookId
        )
        try Task.checkCancellation()
        return (normalizedText.content, buildResult)
    }

    internal nonisolated func buildCancellable(
        originalTitle: String,
        normalizedText: NormalizedChapterText,
        isTranslationEnabled: Bool,
        showTitle: Bool,
        bookId: String
    ) async throws -> ReaderParagraphBuildResult {
        try Task.checkCancellation()

        let titleResult: TranslatedTextResult
        if isTranslationEnabled && TranslateUtils.containsChinese(originalTitle) {
            titleResult = TranslateUtils.translateChapterTitleWithMapping(originalTitle, bookId: bookId)
        } else {
            titleResult = TranslateUtils.untranslatedTextResult(originalTitle)
        }

        var translatedLines: [TranslatedTextResult] = []
        translatedLines.reserveCapacity(normalizedText.lines.count)

        for (index, line) in normalizedText.lines.enumerated() {
            if index % 5 == 0 {
                try Task.checkCancellation()
            }
            let lineResult: TranslatedTextResult
            if isTranslationEnabled && TranslateUtils.containsChinese(line.text) {
                lineResult = TranslateUtils.translateContentWithMapping(line.text, bookId: bookId)
            } else {
                lineResult = TranslateUtils.untranslatedTextResult(line.text)
            }
            translatedLines.append(lineResult)
        }

        try Task.checkCancellation()

        var items: [ParagraphItem] = []
        if showTitle {
            items.append(ParagraphItem(
                id: -1,
                original: originalTitle,
                translated: titleResult.text,
                isTitle: true,
                translationSpans: titleResult.spans
            ))
        }

        items.append(contentsOf: normalizedText.lines.indices.map { index in
            let originalLine = normalizedText.lines[index]
            let translatedLine = translatedLines[index]
            return ParagraphItem(
                id: originalLine.id,
                original: originalLine.text,
                translated: translatedLine.text,
                isTitle: false,
                translationSpans: translatedLine.spans
            )
        })

        return ReaderParagraphBuildResult(
            translatedTitle: titleResult.text,
            translatedContent: translatedLines.map(\.text).joined(separator: "\n"),
            paragraphItems: items
        )
    }

    internal func processAndSaveChapter(
        index: Int,
        originalTitle: String,
        originalContent: String,
        revision: Int
    ) async {
        var targetRevision = revision
        while !Task.isCancelled {
            let activeRevision = self.currentRevision
            if targetRevision != activeRevision {
                targetRevision = activeRevision
            }

            let isTranslationEnabled = self.isTranslationEnabled
            let bookId = self.bookId
            let currentToken = TranslateUtils.translationGenerationToken(for: bookId)
            let showTitleKey = "showChapterTitle_\(bookId)"
            let showTitle = UserDefaults.standard.object(forKey: showTitleKey) != nil
                ? UserDefaults.standard.bool(forKey: showTitleKey)
                : true

            do {
                let (normContent, result) = try await performChapterTranslationOffMainActor(
                    originalTitle: originalTitle,
                    originalContent: originalContent,
                    isTranslationEnabled: isTranslationEnabled,
                    showTitle: showTitle,
                    bookId: bookId
                )

                guard !Task.isCancelled else { return }

                if self.currentRevision == targetRevision,
                   self.isTranslationEnabled == isTranslationEnabled,
                   TranslateUtils.translationGenerationToken(for: bookId) == currentToken {
                    let cached = cache.cache[index] ?? cache.setPlaceholder(index)

                    let isDisplayEqual = cached.originalTitle == originalTitle &&
                        cached.originalContent == normContent &&
                        cached.title == result.translatedTitle &&
                        cached.content == result.translatedContent &&
                        cached.paragraphItems == result.paragraphItems &&
                        cached.isTranslationEnabled == isTranslationEnabled &&
                        cached.state == .loaded

                    if !isDisplayEqual {
                        cached.originalTitle = originalTitle
                        cached.originalContent = normContent
                        cached.title = result.translatedTitle
                        cached.content = result.translatedContent
                        cached.paragraphItems = result.paragraphItems
                        cached.isTranslationEnabled = isTranslationEnabled
                        cached.state = .loaded
                    }
                    cached.revision = targetRevision
                    cached.translationToken = currentToken
                    return
                } else {
                    targetRevision = self.currentRevision
                    continue
                }
            } catch {
                return
            }
        }
    }

    func toggleTranslation(enabled: Bool) {
        self.isTranslationEnabled = enabled
    }

    func updateCachedTranslatedContent(bookId: String, scope: DictionaryInvalidationScope = .globalReload) {
        guard bookId == self.bookId else { return }

        let currentIndex = displayedChapterIndex
        for (idx, cached) in cache.cache {
            if idx != currentIndex {
                cached.translationToken = 0
                cached.title = ""
                cached.content = ""
                cached.paragraphItems = []
            }
        }

        refreshParagraphItems()
    }

    func refreshParagraphItems() {
        translationRefreshTask?.cancel()
        currentRevision += 1
        let taskRevision = currentRevision

        let currentIndex = displayedChapterIndex
        guard let cached = cache.cache[currentIndex], !cached.originalContent.isEmpty else { return }

        let originalTitle = cached.originalTitle
        let originalContent = cached.originalContent

        let isPerfLogging = AppLogger.shared.isLoggingEnabled
        let startUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0

        translationRefreshTask = Task { [weak self] in
            guard let self else { return }

            await self.processAndSaveChapter(
                index: currentIndex,
                originalTitle: originalTitle,
                originalContent: originalContent,
                revision: taskRevision
            )

            if isPerfLogging {
                let endUptime = ProcessInfo.processInfo.systemUptime
                let totalMs = (endUptime - startUptime) * 1000
                let outcome = Task.isCancelled ? "cancelled" : (self.currentRevision != taskRevision ? "superseded" : "completed")
                AppLogger.shared.log(String(format: "[ReaderPerf] TranslationRefresh index=%d totalMs=%.2f outcome=%@", currentIndex, totalMs, outcome))
            }
        }
    }
}
