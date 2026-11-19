import Foundation

@MainActor
final class ReaderTranslationPresentation {
    struct Prepared {
        let index: Int
        let originalTitle: String
        let originalContent: String
        let result: ReaderParagraphBuildResult
        let revision: Int
        let token: Int
        let translationEnabled: Bool
        let convertTraditional: Bool
    }
    var deferred = false
    var pending: Prepared?
}
