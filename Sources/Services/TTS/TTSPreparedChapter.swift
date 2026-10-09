import Foundation

internal struct TTSPreparedChapter: Sendable {
    let normalizedContent: String
    let paragraphs: [TTSParagraph]
}
