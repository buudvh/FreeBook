import SwiftUI

/// Router **duy nhất** chọn màn mở nội dung cho một cuốn sách (bất biến 5 của plan comic/video).
///
/// Nhãn tham số trùng hệt `ReaderView(...)` nên 4 call site (`BookDetailView`, `ShelfView`, `ShelfSearchView`,
/// `CollectionDetailView`) chỉ đổi tên type, giữ nguyên số dòng và modifier (`.id(route.id)`).
///
/// Loại nội dung được suy **một lần** lúc tạo view và ghim bằng `@State`: cài/gỡ tiện ích giữa chừng không làm
/// màn đang mở đổi type (đổi type là SwiftUI dựng lại từ đầu, mất trạng thái đọc).
struct BookContentDestination: View {
    let launch: BookContentLaunch
    @State private var kind: ExtensionContentKind

    init(
        bookId: String,
        extensionPackageId: String,
        chapterIndex: Int,
        onlineChapters: [ChapterResult],
        bookTitle: String?,
        bookAuthor: String?,
        bookCoverUrl: String?,
        bookDesc: String?,
        bookDetailUrl: String?,
        bookSourceName: String?,
        initialParagraphIndex: Int? = nil
    ) {
        self.launch = BookContentLaunch(
            bookId: bookId,
            extensionPackageId: extensionPackageId,
            chapterIndex: chapterIndex,
            onlineChapters: onlineChapters,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            bookCoverUrl: bookCoverUrl,
            bookDesc: bookDesc,
            bookDetailUrl: bookDetailUrl,
            bookSourceName: bookSourceName,
            initialParagraphIndex: initialParagraphIndex
        )
        self._kind = State(initialValue: Self.resolveKind(bookId: bookId, packageId: extensionPackageId))
    }

    /// Tiện ích đã gỡ và không còn trong catalog (vd cài từ zip) thì không tra được loại. Truyện tranh / phim đã tải
    /// offline vẫn phải mở bằng màn comic / trình phát thay vì rơi vào reader chữ.
    /// Nguồn Legado: ghi đè loại **của sách** (`book.type`, spec §13.6) thắng loại của nguồn; tiện ích JS không đổi.
    private static func resolveKind(bookId: String, packageId: String) -> ExtensionContentKind {
        if let override = LegadoBookTypeOverride.shared.contentKind(bookId: bookId, packageId: packageId) { return override }
        if let known = ExtensionContentKind.resolveIfKnown(packageId: packageId) { return known }
        if !ComicOfflineStore.downloadedChapterIndexes(bookId: bookId).isEmpty { return .comic }
        return VideoOfflineStore.downloadedEpisodeIndexes(bookId: bookId).isEmpty ? .text : .video
    }

    var body: some View {
        switch kind {
        case .comic:
            ComicReaderView(launch: launch)
        case .video:
            VideoPlayerScreen(launch: launch)
        case .text, .unsupported:
            ReaderView(
                bookId: launch.bookId,
                extensionPackageId: launch.extensionPackageId,
                chapterIndex: launch.chapterIndex,
                onlineChapters: launch.onlineChapters,
                bookTitle: launch.bookTitle,
                bookAuthor: launch.bookAuthor,
                bookCoverUrl: launch.bookCoverUrl,
                bookDesc: launch.bookDesc,
                bookDetailUrl: launch.bookDetailUrl,
                bookSourceName: launch.bookSourceName,
                initialParagraphIndex: launch.initialParagraphIndex
            )
        }
    }
}
