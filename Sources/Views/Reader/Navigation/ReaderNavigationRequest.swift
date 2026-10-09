import Foundation

struct ReaderNavigationRequest: Equatable {
    let generation: Int
    let chapterIndex: Int
    let paragraphIndex: Int
    let direction: ReaderNavigationDirection
    let source: ReaderNavigationSource
    let persistProgress: Bool
    let forceRefresh: Bool
}
