import Foundation

struct ReaderChapterLoadFailure: Equatable {
    let generation: Int
    let targetChapterIndex: Int
    let chapterTitle: String
    let sourceMessage: String
    let source: ReaderNavigationSource
    let paragraphIndex: Int
    let persistProgress: Bool
    let forceRefresh: Bool
}
