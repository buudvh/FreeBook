import Foundation

struct ReaderNavigationCommit: Equatable {
    let generation: Int
    let chapterIndex: Int
    let paragraphIndex: Int
    let direction: ReaderNavigationDirection
    let source: ReaderNavigationSource
    let animateContent: Bool
}
