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
                    cached.originalTitle = originalTitle
                    cached.originalContent = normContent
                    cached.title = result.translatedTitle
                    cached.content = result.translatedContent
                    cached.paragraphItems = result.paragraphItems
                    cached.revision = targetRevision
                    cached.isTranslationEnabled = isTranslationEnabled
                    cached.translationToken = currentToken
                    cached.state = .loaded
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

    func updateCachedTranslatedContent(bookId: String) {
        guard bookId == self.bookId else { return }
        refreshParagraphItems()
    }

    func refreshParagraphItems() {
        translationRefreshTask?.cancel()
        currentRevision += 1
        let taskRevision = currentRevision

        let currentIndex = displayedChapterIndex
        let allSnapshots = cache.cache.values
            .filter { $0.state == .loaded || !$0.originalContent.isEmpty }
            .map { ($0.index, $0.originalTitle, $0.originalContent) }

        guard !allSnapshots.isEmpty else { return }

        let currentSnapshot = allSnapshots.first(where: { $0.0 == currentIndex })
        let neighborSnapshots = allSnapshots
            .filter { $0.0 != currentIndex }
            .sorted { abs($0.0 - currentIndex) < abs($1.0 - currentIndex) }

        let isPerfLogging = AppLogger.shared.isLoggingEnabled
        let startUptime = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
        let cachedCount = allSnapshots.count
        let neighborCount = neighborSnapshots.count

        translationRefreshTask = Task { [weak self] in
            guard let self else { return }

            let currentStart = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
            if let current = currentSnapshot {
                await self.processAndSaveChapter(
                    index: current.0,
                    originalTitle: current.1,
                    originalContent: current.2,
                    revision: taskRevision
                )
            }
            let currentEnd = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0

            if Task.isCancelled || self.currentRevision != taskRevision {
                if isPerfLogging {
                    let endUptime = ProcessInfo.processInfo.systemUptime
                    let currentMs = (currentEnd - currentStart) * 1000
                    let totalMs = (endUptime - startUptime) * 1000
                    let outcome = Task.isCancelled ? "cancelled" : "superseded"
                    let logLine = String(format: "[ReaderPerf] TranslationRefresh cachedCount=%d neighborCount=%d currentMs=%.2f neighborsMs=0.00 totalMs=%.2f outcome=%@", cachedCount, neighborCount, currentMs, totalMs, outcome)
                    AppLogger.shared.log(logLine)
                }
                return
            }

            let neighborStart = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0
            for neighbor in neighborSnapshots {
                if Task.isCancelled || self.currentRevision != taskRevision {
                    break
                }
                await self.processAndSaveChapter(
                    index: neighbor.0,
                    originalTitle: neighbor.1,
                    originalContent: neighbor.2,
                    revision: taskRevision
                )
                await Task.yield()
            }
            let neighborEnd = isPerfLogging ? ProcessInfo.processInfo.systemUptime : 0

            if isPerfLogging {
                let endUptime = ProcessInfo.processInfo.systemUptime
                let currentMs = (currentEnd - currentStart) * 1000
                let neighborsMs = (neighborEnd - neighborStart) * 1000
                let totalMs = (endUptime - startUptime) * 1000
                let outcome: String
                if Task.isCancelled {
                    outcome = "cancelled"
                } else if self.currentRevision != taskRevision {
                    outcome = "superseded"
                } else {
                    outcome = "completed"
                }
                let logLine = String(format: "[ReaderPerf] TranslationRefresh cachedCount=%d neighborCount=%d currentMs=%.2f neighborsMs=%.2f totalMs=%.2f outcome=%@", cachedCount, neighborCount, currentMs, neighborsMs, totalMs, outcome)
                AppLogger.shared.log(logLine)
            }
        }
    }
}
