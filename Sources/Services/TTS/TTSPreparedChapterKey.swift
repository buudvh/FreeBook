import Foundation

internal struct TTSPreparedChapterKey: Equatable, Sendable {
    let bookId: String
    let chapterIndex: Int
    let chapterTitle: String
    let content: String
    let chunkLength: Int
    let includeChapterTitle: Bool
    let removeDuplicatedTitle: Bool
    let isTranslationEnabled: Bool
    let shouldConvertTraditionalToSimplified: Bool
    let translationToken: Int
}
