import SwiftUI

/// Matcher thuần cho tìm kiếm sách trong Kệ sách & Lịch sử (và sheet chọn truyện của Từ điển).
/// Khớp query với: tên gốc, tên đã dịch, tác giả, tác giả đã phiên âm — cộng tên / tác giả **đã chuyển phồn → giản**
/// khi truyện bật phồn → giản (1.3.846: đó là chữ hàng đang hiện khi tắt dịch).
/// Không phụ thuộc trạng thái toggle dịch — các cột `titleTrans`/`authorTrans` (đã qua phồn → giản của truyện) được
/// backfill lúc mở app bởi `BookTitleTranslationMigrator`.
enum ShelfBookSearchMatcher {
    static func matches(
        query: String,
        title: String,
        titleTrans: String,
        author: String,
        authorTrans: String
    ) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return title.localizedCaseInsensitiveContains(q)
            || titleTrans.localizedCaseInsensitiveContains(q)
            || author.localizedCaseInsensitiveContains(q)
            || authorTrans.localizedCaseInsensitiveContains(q)
    }

    /// Truyện đã lưu. `config` chụp **một lần** mỗi lượt lọc (`TranslationConfigStore.shared.snapshot()`), không chụp
    /// từng truyện.
    static func matches(query: String, book: Book, config: TranslationConfigSnapshot) -> Bool {
        if matches(
            query: query,
            title: book.title,
            titleTrans: book.titleTrans,
            author: book.author,
            authorTrans: book.authorTrans
        ) {
            return true
        }
        guard config.convertsTraditional(bookId: book.bookId, packageId: book.extensionPackageId) else { return false }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return false }
        return ChineseTextPipeline.convert(book.title, converts: true).localizedCaseInsensitiveContains(q)
            || ChineseTextPipeline.convert(book.author, converts: true).localizedCaseInsensitiveContains(q)
    }
}
