import Foundation

enum ReaderNavigationSource: Equatable {
    case history
    case previousButton
    case nextButton
    case chapterList
    case ttsSync
    case reload

    var isImmediate: Bool {
        switch self {
        case .history, .ttsSync, .reload, .previousButton, .nextButton, .chapterList:
            return true
        }
    }
}
