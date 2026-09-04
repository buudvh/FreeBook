import SwiftUI

/// Nút tải **từng chương** của danh sách chương (1.3.334).
///
/// Cố ý **không** đi qua `ReaderViewModel.loadChapterContentFromExtension`: đường đó còn dịch cả
/// chương và dựng `[ParagraphItem]` để hiển thị, tức là trả giá CPU của việc *mở* chương cho một việc
/// chỉ cần *ghi nội dung xuống máy*. `ChapterContentRepository.load` đã tự ghi nền qua
/// `enqueueWrite`, nên chỉ cần gọi nó.
extension ReaderChapterListView {

    /// Chỉ truyện đã có trong kệ mới tải lẻ được: truyện đang xem online chưa có hàng `Book` để gắn
    /// nội dung vào, còn TXT nội bộ thì không có URL nào để tải.
    internal var canDownloadChapters: Bool {
        !isLocalTXTBook && ext != nil && localBook != nil
    }

    internal func downloadChapter(_ chapter: ReaderChapterRowState) {
        guard canDownloadChapters, let ext else { return }
        guard !chapter.isPlaceholder, !chapter.isCached else { return }

        let url = chapter.url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else {
            ToastManager.shared.show(message: "Chương này chưa có đường dẫn để tải", type: .error)
            return
        }

        let index = chapter.index
        guard !downloadingChapterIndices.contains(index) else { return }
        downloadingChapterIndices.insert(index)

        let container = modelContext.container
        let extensionInfo = TTSExtensionInfo(
            packageId: ext.packageId,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let title = chapter.title
        let fallbackHost = localBook?.host

        Task {
            defer { downloadingChapterIndices.remove(index) }

            await ChapterContentRepository.shared.configure(container: container)
            // Host của **đúng** hàng chương, không phải host của truyện: vài nguồn đổi domain giữa các
            // chương nên lấy sai host là bóc tách trượt.
            let row = try? await ChapterStore.shared.fetchChapter(bookId: bookId, index: index, url: url)

            do {
                _ = try await ChapterContentRepository.shared.load(
                    ChapterContentRequest(
                        bookId: bookId,
                        chapterIndex: index,
                        title: title,
                        url: url,
                        host: row?.host ?? fallbackHost,
                        bookMetadata: nil,
                        extensionInfo: extensionInfo,
                        forceRefresh: false
                    )
                )
                store.markCached(index: index)
                ToastManager.shared.show(message: "Đã tải chương \(index + 1)", type: .success)
            } catch is CancellationError {
                return
            } catch {
                ToastManager.shared.show(
                    message: "Không tải được chương \(index + 1): \(error.localizedDescription)",
                    type: .error
                )
            }
        }
    }
}
