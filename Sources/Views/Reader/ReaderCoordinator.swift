import Foundation
import Combine

@available(iOS 17.0, *)
@MainActor
final class ReaderCoordinator: ObservableObject {
    private let viewModel: ReaderViewModel

    init(viewModel: ReaderViewModel) {
        self.viewModel = viewModel
    }

    var readingContext: ReadingContext {
        viewModel.readingContext
    }

    var windowIndexes: [Int] {
        viewModel.stableIndexes
    }

    func jumpToChapter(_ index: Int, paragraphIndex: Int = -1) {
        viewModel.jumpToChapter(index, paragraphIndex: paragraphIndex)
    }

    func updateVisibleLocation(chapterIndex: Int, paragraphIndex: Int) {
        viewModel.updateActiveLocationFromScroll(chapterIndex: chapterIndex, paragraphIndex: paragraphIndex)
    }

    func saveProgressImmediately() {
        viewModel.saveProgressImmediately()
    }
}
