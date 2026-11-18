import Foundation

/// Nạp một chương cho "Tìm trong chương" (1.3.980, anh Bửu: "load vô hạn 2 đầu, đầu trên sẽ tìm tiếp trang trước, đầu dưới
/// sẽ load trang sau"; chương chưa tải về máy ⇒ "tải từ nguồn rồi tìm").
///
/// - Chương đã dựng sẵn trong RAM (`cache`, `state == .loaded`) ⇒ dùng luôn các đoạn đang hiển thị.
/// - Còn lại ⇒ **cùng đường** với Reader: `chapterContentRequest` + `ChapterContentRepository.load` (RAM chung → file đã tải →
///   tải qua tiện ích; tải từ nguồn thì chương được lưu lại như lúc đọc, mục lục đánh dấu "đã tải") rồi
///   `performChapterTranslationOffMainActor` với đúng cài đặt dịch / phồn → giản / tiêu đề hiện tại ⇒ cùng `ParagraphItem.id`
///   với lúc mở chương đó trong Reader, bấm kết quả là nhảy đúng đoạn.
/// - **Không** ghi vào `cache` của Reader (cửa sổ trượt, bộ nhớ, chương đang đọc giữ nguyên).
extension ReaderViewModel {
    /// `title` là tên **gốc** của chương — `ReaderView` dịch nó như tên ở đầu trang (`chapterHeaderTitle`).
    func loadChapterForSearch(_ index: Int) async throws -> ReaderSearchMatcher.LoadedChapter {
        guard index >= 0 && index < totalChaptersCount else {
            throw ReaderLoadError.invalidChapterIndex(index, total: totalChaptersCount)
        }
        if let cached = cache.cache[index], cached.state == .loaded, !cached.paragraphItems.isEmpty {
            return ReaderSearchMatcher.LoadedChapter(
                chapter: Self.searchChapter(index: index, items: cached.paragraphItems),
                title: cached.originalTitle.isEmpty ? chapterTitle(at: index) : cached.originalTitle
            )
        }

        let (request, title) = try await chapterContentRequest(at: index, forceRefresh: false, interactive: false)
        await ChapterContentRepository.shared.configure(container: modelContext.container)
        let result = try await ChapterContentRepository.shared.load(request)
        try Task.checkCancellation()
        if result.origin == .extensionFetch {
            noteChapterFetchedFromSource(index)
        }

        let isTranslationEnabled = self.isTranslationEnabled
        let layout = Self.chapterTitleLayout(bookId: bookId)
        let (_, build) = try await performChapterTranslationOffMainActor(
            originalTitle: title,
            originalContent: result.document.text.content,
            isTranslationEnabled: isTranslationEnabled,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
            showTitle: layout.showTitle,
            removeDuplicatedTitle: layout.removeDuplicatedTitle,
            bookId: bookId,
            chapterIndex: index,
            extensionEngine: extensionTranslationEngine(isTranslationEnabled: isTranslationEnabled)
        )
        try Task.checkCancellation()
        return ReaderSearchMatcher.LoadedChapter(
            chapter: Self.searchChapter(index: index, items: build.paragraphItems),
            title: title
        )
    }

    /// Đoạn của một chương ở dạng phẳng cho bộ khớp — dùng cho cả snapshot RAM lúc mở sheet lẫn chương nạp thêm.
    nonisolated static func searchChapter(index: Int, items: [ParagraphItem]) -> ReaderSearchMatcher.Chapter {
        ReaderSearchMatcher.Chapter(chapterIndex: index, paragraphs: items.map { item in
            ReaderSearchMatcher.Paragraph(
                paragraphIndex: item.id,
                isTitle: item.isTitle,
                original: item.original,
                translated: item.translated
            )
        })
    }
}
