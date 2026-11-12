import Foundation

public struct ProcessedChapterDTO: Sendable {
    public let bookId: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let normalizedContent: String
    public let paragraphs: [TTSParagraph]
    public let sessionID: UUID
    public let generation: Int
    public let translationToken: Int
}

public actor TTSBackgroundProcessor {
    public init() {}
    
    public func processChapter(
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String,
        rawContent: String,
        chunkLength: Int,
        shouldTranslateRawContent: Bool,
        shouldConvertTraditionalToSimplified: Bool = false,
        includeChapterTitle: Bool,
        removeDuplicatedTitle: Bool,
        sessionID: UUID,
        generation: Int,
        snapshot: TTSPretranslatedSnapshot? = nil,
        translatedTitleOverride: String? = nil
    ) throws -> ProcessedChapterDTO {
        if TranslationReadContext.current == nil || TranslationReadContext.current?.bookId != bookId {
            return try TranslationReadContext.withSnapshot(bookId: bookId) {
                try processChapter(bookId: bookId, chapterIndex: chapterIndex, chapterTitle: chapterTitle,
                    rawContent: rawContent, chunkLength: chunkLength, shouldTranslateRawContent: shouldTranslateRawContent,
                    shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
                    includeChapterTitle: includeChapterTitle, removeDuplicatedTitle: removeDuplicatedTitle,
                    sessionID: sessionID, generation: generation, snapshot: snapshot,
                    translatedTitleOverride: translatedTitleOverride)
            }
        }
        try Task.checkCancellation()

        // 1. Normalize raw content to get lines with IDs. Phồn → giản chạy trước, cả khi tắt dịch (1.3.846) — đúng hàm +
        // đúng cờ của Reader (`ReaderViewModel.performChapterTranslationOffMainActor`) ⇒ cùng dòng, cùng chữ để highlight.
        let rawNormalized = ChineseTextPipeline.normalizeChapter(rawContent, converts: shouldConvertTraditionalToSimplified)
        let options = ChineseTextPipeline.Options(
            converts: shouldConvertTraditionalToSimplified, translates: shouldTranslateRawContent, dictionaryBookId: bookId
        )

        try Task.checkCancellation()

        // 1b. Optional: drop the first line when it is a chapter title recognized by the
        // active TOC rules (same detection as TXT import), so the title is not read twice.
        let lines = ChapterTextNormalizer.contentLines(of: rawNormalized, removingDuplicatedTitle: removeDuplicatedTitle)

        // 2. Per-line processing & title processing
        let lineEntries: [TTSLineEntry]
        let simpleEntries: [(id: Int, text: String)]

        let currentToken = TranslationReadContext.cacheGeneration(for: bookId)
        if let snapshot = snapshot,
           snapshot.matches(lines: lines, isTranslationEnabled: shouldTranslateRawContent,
                            convertsTraditional: shouldConvertTraditionalToSimplified, token: currentToken) {
            lineEntries = snapshot.entries
            simpleEntries = snapshot.entries.map { (id: $0.lineId, text: $0.translatedText) }
        } else if shouldTranslateRawContent {
            if snapshot != nil, translatedTitleOverride != nil {
                AppLogger.shared.log("❌ [ExtTranslate] TTS chương \(chapterIndex + 1): bản dịch tiện ích lệch dòng ⇒ đọc bản QT")
            }
            let mapped = try lines.map { line -> (TTSLineEntry, (id: Int, text: String)) in
                try Task.checkCancellation()
                if TranslateUtils.containsChinese(line.text) {
                    let result = ChineseTextPipeline.contentWithMapping(line.text, options.alreadyConverted)
                    let entry = TTSLineEntry(lineId: line.id, originalText: line.text, translatedText: result.text, spans: result.spans)
                    return (entry, (id: line.id, text: result.text))
                } else {
                    let entry = TTSLineEntry(lineId: line.id, originalText: line.text, translatedText: line.text, spans: [])
                    return (entry, (id: line.id, text: line.text))
                }
            }
            lineEntries = mapped.map(\.0)
            simpleEntries = mapped.map(\.1)
        } else {
            lineEntries = lines.map { TTSLineEntry(lineId: $0.id, originalText: $0.text, translatedText: $0.text, spans: []) }
            simpleEntries = lines.map { (id: $0.id, text: $0.text) }
        }

        let processedTitle: String
        if shouldTranslateRawContent, let translatedTitleOverride, !translatedTitleOverride.isEmpty {
            // Tên chương đã dịch bằng tiện ích dịch (`TTSExtensionTranslationPreparer`) — không dịch QT lại.
            processedTitle = translatedTitleOverride
        } else {
            // Tắt dịch ⇒ tên đã chuyển (như tên chương Reader dựng ở đoạn id -1).
            processedTitle = ChineseTextPipeline.chapterTitle(chapterTitle, options)
        }

        try Task.checkCancellation()

        // 3. Reconstruct gap-preserved content and normalize processed content without junk filter
        let gapPreservedContent = ChapterTextNormalizer.reconstructContentPreservingLineIDs(from: simpleEntries)

        try Task.checkCancellation()

        // 4. Segment into clean chunks
        var paragraphs = TTSParagraphBuilder.buildFromEntries(lineEntries, chunkLength: chunkLength)

        try Task.checkCancellation()

        // 5. Optionally insert chapter title at paragraphIndex = -1
        if includeChapterTitle && !processedTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: processedTitle,
                range: NSRange(location: 0, length: processedTitle.utf16.count),
                paragraphIndex: -1,
                sourceRange: NSRange(location: 0, length: max(0, chapterTitle.utf16.count))
            )
            paragraphs.insert(titleParagraph, at: 0)
        }
        
        return ProcessedChapterDTO(
            bookId: bookId,
            chapterIndex: chapterIndex,
            chapterTitle: processedTitle,
            normalizedContent: gapPreservedContent,
            paragraphs: paragraphs,
            sessionID: sessionID,
            generation: generation,
            translationToken: currentToken
        )
    }
}
