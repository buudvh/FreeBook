import SwiftUI

/// Mở rộng `ReaderView` tích hợp màn hình toàn màn hình AI Agent Harness.
extension ReaderView {
    @ViewBuilder
    internal var aiFullScreenDestination: some View {
        ReaderAIFullScreenView(
            bookId: bookId,
            bookTitle: readerBookDisplayTitle,
            chapterIndex: readerPresentedChapterIndex,
            chapterTitle: readerChapterDisplayTitle,
            currentChapterRawContent: currentChapterRawContentForAI
        )
    }

    /// Mở màn hình AI Agent thông qua AIRuntimeCoordinator toàn cục.
    internal func openAIFromReader() {
        let context = AIRuntimeCoordinator.ActiveContext(
            bookId: bookId,
            bookTitle: readerBookDisplayTitle,
            chapterIndex: readerPresentedChapterIndex,
            chapterTitle: readerChapterDisplayTitle,
            currentChapterRawContent: currentChapterRawContentForAI
        )
        AIRuntimeCoordinator.shared.updateContext(context)
        AIRuntimeCoordinator.shared.presentFullScreen(context: context)
    }

    /// Lấy toàn bộ nội dung raw (chưa dịch) của chương đang hiển thị.
    internal var currentChapterRawContentForAI: String {
        guard let cached = viewModel?.cache.get(readerPresentedChapterIndex) else {
            return ""
        }
        let contentItems = cached.paragraphItems.filter { !$0.isTitle }
        if !contentItems.isEmpty {
            return contentItems.map { $0.original }.joined(separator: "\n")
        }
        return cached.originalContent
    }
}
