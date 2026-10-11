import SwiftUI

/// Lớp vỏ **không có trạng thái** của `ReaderChapterListView`, chỉ để mang phép so `==` cho `.equatable()`.
///
/// Danh sách chương được giữ mounted suốt phiên Reader (ẩn bằng opacity/offset), nên nếu không chặn thì mỗi
/// pass body của `ReaderView` (nhịp highlight TTS, publish VM) đều dựng lại header + `List` của nó.
///
/// **Lỗi thật 1.3.510** — vì sao `==` phải nằm ở vỏ, không đặt trên chính `ReaderChapterListView`: commit
/// `c9e7c20a` cho view thật (có `@State searchQuery` và đọc store `@Observable`) conform `Equatable` rồi bọc
/// `.equatable()`. Kết quả trên máy: gõ ô "Tìm kiếm chương..." danh sách không đổi, dù truy vấn đã trả đúng kết
/// quả vào store; phải đóng rồi mở lại danh sách (input `isPresented` đổi làm `==` khác) thì kết quả mới hiện.
/// Các `@State` nội bộ khác (đảo thứ tự, đang cập nhật mục lục, đang tải chương lẻ) kẹt cùng kiểu. Khuôn đúng:
/// `==` đặt ở vỏ này (không `@State`, không đọc store); view thật bên trong **không** `Equatable` nên `@State`
/// và Observation cập nhật bình thường, còn nhịp vẽ lại của `ReaderView` vẫn bị chặn ở đây.
///
/// `==` so **mọi** input giá trị; class (`@Model`, store `@Observable`) so theo identity. Closure bị bỏ qua, cùng
/// hợp đồng với `ParagraphCardView`. Thêm stored property mới thì phải thêm vào `==`.
struct ReaderChapterListHost: View, Equatable {
    let bookId: String
    let bookTitle: String?
    let bookAuthor: String?
    let bookCoverUrl: String?
    let bookDetailUrl: String?
    let localBook: Book?
    let ext: Extension?
    let currentChapterIndex: Int
    let isPresented: Bool
    let isTranslationEnabled: Bool
    let shouldConvertTraditionalToSimplified: Bool
    let theme: ReaderTheme
    let store: ReaderChapterListStore
    @Binding var onlineChapters: [ChapterResult]
    let isLocalTXTBook: Bool
    let onSelectChapter: (Int) -> Void
    let onClose: () -> Void
    let onLocalTOCRefreshed: ((LocalTOCRefreshResult) -> Void)?

    var body: some View {
        ReaderChapterListView(
            bookId: bookId,
            bookTitle: bookTitle,
            bookAuthor: bookAuthor,
            bookCoverUrl: bookCoverUrl,
            bookDetailUrl: bookDetailUrl,
            localBook: localBook,
            ext: ext,
            currentChapterIndex: currentChapterIndex,
            isPresented: isPresented,
            isTranslationEnabled: isTranslationEnabled,
            shouldConvertTraditionalToSimplified: shouldConvertTraditionalToSimplified,
            theme: theme,
            store: store,
            onlineChapters: $onlineChapters,
            isLocalTXTBook: isLocalTXTBook,
            onSelectChapter: onSelectChapter,
            onClose: onClose,
            onLocalTOCRefreshed: onLocalTOCRefreshed
        )
    }

    static func == (lhs: ReaderChapterListHost, rhs: ReaderChapterListHost) -> Bool {
        return lhs.bookId == rhs.bookId &&
               lhs.bookTitle == rhs.bookTitle &&
               lhs.bookAuthor == rhs.bookAuthor &&
               lhs.bookCoverUrl == rhs.bookCoverUrl &&
               lhs.bookDetailUrl == rhs.bookDetailUrl &&
               lhs.localBook === rhs.localBook &&
               lhs.ext === rhs.ext &&
               lhs.currentChapterIndex == rhs.currentChapterIndex &&
               lhs.isPresented == rhs.isPresented &&
               lhs.isTranslationEnabled == rhs.isTranslationEnabled &&
               lhs.shouldConvertTraditionalToSimplified == rhs.shouldConvertTraditionalToSimplified &&
               lhs.theme == rhs.theme &&
               lhs.store === rhs.store &&
               lhs.onlineChapters == rhs.onlineChapters &&
               lhs.isLocalTXTBook == rhs.isLocalTXTBook
    }
}
