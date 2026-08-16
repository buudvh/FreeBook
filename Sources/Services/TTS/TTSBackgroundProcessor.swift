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

public typealias TTSProcessedChapter = ProcessedChapterDTO

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
        removeDuplicatedTitle: Bool,
        sessionID: UUID,
        generation: Int,
        snapshot: TTSPretranslatedSnapshot? = nil
    ) throws -> ProcessedChapterDTO {
        try Task.checkCancellation()

        // 1. Normalize raw content to get lines with IDs
        let rawNormalized = ChapterTextNormalizer.normalize(rawContent)

        try Task.checkCancellation()

        // 1b. Optional: drop the first line when it is a chapter title recognized by the
        // active TOC rules (same detection as TXT import), so the title is not read twice.
        var lines = rawNormalized.lines
        if removeDuplicatedTitle, let first = lines.first {
            let compiledTOCRegexes = TranslateUtils.getCompiledActiveTOCRegexes()
            if TranslateUtils.isChapterHeaderLine(first.text, compiledTOCRegexes: compiledTOCRegexes) {
                lines.removeFirst()
            }
        }

        // 2. Per-line processing & title processing
        let lineEntries: [TTSLineEntry]
        let simpleEntries: [(id: Int, text: String)]

        let currentToken = TranslateUtils.translationGenerationToken(for: bookId)
        if let snapshot = snapshot,
           snapshot.isTranslationEnabled == shouldTranslateRawContent,
           snapshot.translationToken == currentToken,
           snapshot.entries.count == lines.count,
           zip(snapshot.entries, lines).allSatisfy({ $0.0.lineId == $0.1.id && $0.0.originalText == $0.1.text }) {
            lineEntries = snapshot.entries
            simpleEntries = snapshot.entries.map { (id: $0.lineId, text: $0.translatedText) }
        } else if shouldTranslateRawContent {
            let mapped = lines.map { line -> (TTSLineEntry, (id: Int, text: String)) in
                if TranslateUtils.containsChinese(line.text) {
                    let result = TranslateUtils.translateContentWithMapping(line.text, bookId: bookId)
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
        if !chapterTitle.isEmpty && shouldTranslateRawContent && TranslateUtils.containsChinese(chapterTitle) {
            processedTitle = TranslateUtils.translateChapterTitle(chapterTitle, bookId: bookId)
        } else {
            processedTitle = chapterTitle
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
            generation: generation
        )
    }
}
