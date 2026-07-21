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
    public static let shared = TTSBackgroundProcessor()
    
    private init() {}
    
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
    ) -> ProcessedChapterDTO {
        // 1. Vietphrase translation if enabled
        let translatedContent: String
        if shouldTranslateRawContent && TranslateUtils.containsChinese(rawContent) {
            translatedContent = TranslateUtils.translateContent(rawContent, bookId: bookId)
        } else {
            translatedContent = rawContent
        }
        
        // 2. Text normalization
        let normalized = ChapterTextNormalizer.normalize(translatedContent)
        
        // 3. Segment into clean paragraphs
        var paragraphs = TTSParagraphBuilder.build(from: normalized, chunkLength: chunkLength)
        
        // 4. Optionally insert chapter title at paragraphIndex = -1
        if includeChapterTitle && !chapterTitle.isEmpty {
            let titleParagraph = TTSParagraph(
                text: chapterTitle,
                range: NSRange(location: 0, length: chapterTitle.utf16.count),
                paragraphIndex: -1
            )
            paragraphs.insert(titleParagraph, at: 0)
        }
        
        return ProcessedChapterDTO(
            bookId: bookId,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            normalizedContent: normalized.content,
            paragraphs: paragraphs,
            sessionID: sessionID,
            generation: generation
        )
    }
}
