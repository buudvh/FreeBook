import Foundation

/// Ngữ cảnh truyện/chương cho `SourceRuntime.comicPages` (tách khỏi file chính để giữ dưới giới hạn dòng).
/// Tiện ích JS bỏ qua; nguồn Legado dùng cho kho biến theo truyện/chương và đối tượng `book`/`chapter` của JS.
/// `interactive`: chỉ `true` cho chương **đang mở** (người dùng đang nhìn); tải trước chương kế giữ `false`.
extension ComicReaderViewModel {
    func sourceContext(for chapter: ComicChapterEntry, interactive: Bool = false) -> SourceRuntimeContext {
        SourceRuntimeContext(
            bookId: launch.bookId,
            bookUrl: launch.bookDetailUrl,
            bookName: launch.bookTitle,
            bookAuthor: launch.bookAuthor,
            chapterTitle: chapter.title,
            chapterIndex: chapter.index,
            isInteractive: interactive
        )
    }
}
