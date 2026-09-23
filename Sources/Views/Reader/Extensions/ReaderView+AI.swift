import SwiftUI

/// Mở rộng `ReaderView` tích hợp màn hình toàn màn hình AI Agent Harness.
extension ReaderView {
    @ViewBuilder
    internal func aiHarnessOverlay(in geometry: GeometryProxy) -> some View {
        EmptyView()
            .fullScreenCover(isPresented: $showingAIFullScreen) {
                ReaderAIFullScreenView(
                    bookId: bookId,
                    bookTitle: readerBookDisplayTitle,
                    chapterIndex: readerPresentedChapterIndex,
                    chapterTitle: readerChapterDisplayTitle,
                    currentChapterRawContent: currentChapterRawContentForAI
                )
            }
    }

    /// Lấy toàn bộ nội dung raw (chưa dịch) của chương đang hiển thị.
    internal var currentChapterRawContentForAI: String {
        guard let vm = viewModel,
              let cached = vm.cachedChapters.first(where: { $0.index == readerPresentedChapterIndex }) else {
            return ""
        }
        return cached.paragraphItems.map { $0.original }.joined(separator: "\n")
    }
}
