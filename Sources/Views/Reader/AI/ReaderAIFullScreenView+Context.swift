import Foundation

/// Ngữ cảnh mở lại màn AI của truyện này, dựng từ chính các tham số của màn (1.3.969).
///
/// Màn AI hiện ⇒ `AIRuntimeCoordinator.screenDidAppear` ghi ngữ cảnh này, ở **mọi** lối mở (nút AI của Reader, Reader mở
/// lại qua `reopenReaderAI`, hub mở bằng UIKit). Trước đó chỉ nút AI của Reader ghi (`ReaderView.openAIFromReader`), nên
/// màn mở lại từ hub / Reader mà người dùng dừng rồi chạy lại quét thì ngữ cảnh bị `pruneContexts` dọn lúc lượt cũ kết thúc
/// (truyện không phải "mở AI gần nhất") trong khi lượt mới vẫn chạy ⇒ hub báo "Không có ngữ cảnh" (log build 1293,
/// anh Bửu: chạy AI từ 2 truyện trở lên, chạm truyện chạy trước ở hub không mở được).
extension ReaderAIFullScreenView {
    var runtimeContext: AIRuntimeCoordinator.ActiveContext {
        AIRuntimeCoordinator.ActiveContext(
            bookId: bookId,
            bookTitle: bookTitle,
            chapterIndex: chapterIndex,
            chapterTitle: chapterTitle,
            currentChapterRawContent: currentChapterRawContent,
            translatesChapterTitles: translatesChapterTitles,
            convertsTraditionalToSimplified: convertsTraditionalToSimplified
        )
    }
}
