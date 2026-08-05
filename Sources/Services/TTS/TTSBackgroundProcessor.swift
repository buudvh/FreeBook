import Foundation

public struct ProcessedChapterDTO: Sendable {
    public let bookId: String
    public let chapterIndex: Int
    public let chapterTitle: String
    public let normalizedContent: String
    public let paragraphs: [TTSParagraph]
    public let sessionID: UUID
    public let generation: Int
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
        includeChapterTitle: Bool,
        sessionID: UUID,
        generation: Int
    ) throws -> ProcessedChapterDTO {
        try Task.checkCancellation()

        // 1. Normalize raw content to get lines with IDs
        let rawNormalized = ChapterTextNormalizer.normalize(rawContent)

        try Task.checkCancellation()

        // 2. Per-line processing & title processing
        let entries: [(id: Int, text: String)]
        if shouldTranslateRawContent {
            entries = rawNormalized.lines.map { (id: $0.id, text: TranslateUtils.translateContent($0.text, bookId: bookId)) }
        } else {
            entries = rawNormalized.lines.map { (id: $0.id, text: $0.text) }
        }

        let processedTitle: String
        if !chapterTitle.isEmpty && shouldTranslateRawContent && TranslateUtils.containsChinese(chapterTitle) {
            processedTitle = TranslateUtils.translateChapterTitle(chapterTitle, bookId: bookId)
        } else {
            processedTitle = chapterTitle
        }

        try Task.checkCancellation()

        // 3. Reconstruct gap-preserved content and normalize processed content without junk filter
        let gapPreservedContent = ChapterTextNormalizer.reconstructContentPreservingLineIDs(from: entries)
        let finalNormalized = ChapterTextNormalizer.normalizeProcessedContent(gapPreservedContent)

        try Task.checkCancellation()

        // 4. Segment into clean chunks
        var paragraphs = TTSParagraphBuilder.build(from: finalNormalized, chunkLength: chunkLength)

        try Task.checkCancellation()

        // 5. Optionally insert chapter title at paragraphIndex = -1
        if includeChapterTitle && !processedTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: processedTitle,
                range: NSRange(location: 0, length: processedTitle.utf16.count),
                paragraphIndex: -1
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
            generation: generation
        )
    }
}
