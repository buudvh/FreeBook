import Foundation

struct ReaderParagraphBuildResult: Equatable, Sendable {
    let translatedTitle: String
    let translatedContent: String
    let paragraphItems: [ParagraphItem]
}
