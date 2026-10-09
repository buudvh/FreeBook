import SwiftUI

/// `ReaderChapterListView` được giữ mounted (ẩn bằng opacity/offset) suốt phiên Reader sau lần mở
/// đầu, nên nếu không `Equatable` thì mỗi pass body của `ReaderView` (nhịp highlight TTS, publish VM)
/// đều dựng lại header + `List` của nó. `==` so **mọi** input giá trị; class (`@Model`, store
/// `@Observable`) so theo identity — thay đổi bên trong chúng vẫn tới body qua Observation. Closure
/// bị bỏ qua, cùng hợp đồng với `ParagraphCardView`. Thêm stored property mới thì phải thêm vào đây.
extension ReaderChapterListView: Equatable {
    public static func == (lhs: ReaderChapterListView, rhs: ReaderChapterListView) -> Bool {
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
