import Foundation
import SwiftData

/// Backfill `titleTrans`/`authorTrans` cho những sách còn để trống.
///
/// Chạy mỗi lần mở app sau khi từ điển đã nạp xong (mirror pattern nạp dict ban đầu
/// trong `TranslationManager.init`). Chỉ xử lý sách còn rỗng nên lần đầu chạy hết,
/// các lần sau no-op. Hai cột này phục vụ tìm kiếm và không phụ thuộc trạng thái
/// toggle dịch (luôn lưu tên đã dịch/phương âm để search bất kể bật/tắt).
///
/// Từ 1.3.846 hai cột tính **sau** bước phồn → giản theo cấu hình của truyện (`searchTranslations`): đổi phồn → giản ở
/// popup dịch thì tính lại cho các truyện vừa đổi (`refresh(bookIds:container:)`), cộng một lượt một lần lúc mở app cho
/// truyện đang bật phồn → giản (`convertMigrationDoneKey`).
public enum BookTitleTranslationMigrator {
    /// Cờ lượt một lần sau 1.3.846: tính lại hai cột cho truyện đang bật phồn → giản (trước đó tính không chuyển).
    static let convertMigrationDoneKey = "bookTitleTransConvertMigrationV1"

    public static func runIfNeeded(container: ModelContainer) async {
        // Chỉ dịch được khi từ điển VietPhrase đã sẵn sàng; nếu chưa thì bỏ qua,
        // lần mở app kế tiếp sẽ chạy lại.
        guard TranslationManager.shared.isVietPhraseLoaded else { return }

        let backfill = BookTitleTranslationBackfill(container: container)
        await backfill.backfill()

        // Xong (lưu được) mới ghi cờ ⇒ app tắt giữa chừng thì lần mở sau chạy lại (tính lại thừa vô hại).
        guard !UserDefaults.standard.bool(forKey: convertMigrationDoneKey) else { return }
        if await backfill.refresh(bookIds: nil), !Task.isCancelled {
            UserDefaults.standard.set(true, forKey: convertMigrationDoneKey)
        }
    }

    /// Tính lại hai cột cho các truyện vừa đổi phồn → giản (popup dịch — `TranslationTraditionalDraft`), trên
    /// `ModelContext` riêng như lượt backfill. Từ điển chưa nạp ⇒ bỏ qua (bản dịch sẽ chỉ là chữ Hán).
    public static func refresh(bookIds: [String], container: ModelContainer) async {
        guard !bookIds.isEmpty, TranslationManager.shared.isVietPhraseLoaded else { return }
        await BookTitleTranslationBackfill(container: container).refresh(bookIds: Set(bookIds))
    }

    /// Công thức **duy nhất** của `titleTrans` / `authorTrans`: **luôn** dịch / phiên âm (không theo công tắc dịch — cột để
    /// tìm), nhưng chuyển phồn → giản trước theo cấu hình của truyện (Truyện ⇒ Nguồn ⇒ Tất cả, `ChineseTextPipeline`) —
    /// cùng chữ với tên đang hiện khi bật phồn → giản. `config` chụp một lần cho cả lượt nhiều truyện.
    static func searchTranslations(
        title: String,
        author: String,
        bookId: String,
        packageId: String?,
        in config: TranslationConfigSnapshot? = nil
    ) -> (title: String, author: String) {
        let snapshot = config ?? TranslationConfigStore.shared.snapshot()
        let options = ChineseTextPipeline.Options(
            converts: snapshot.convertsTraditional(bookId: bookId, packageId: packageId),
            translates: true,
            dictionaryBookId: bookId.isEmpty ? nil : bookId
        )
        return (ChineseTextPipeline.meta(title, options), ChineseTextPipeline.author(author, options))
    }

    /// Cập nhật lại `titleTrans`/`authorTrans` cho một cuốn sách ngay khi mở từ
    /// Kệ sách / màn hình chi tiết — không chờ migration lần mở app kế tiếp.
    /// Bỏ qua nếu từ điển chưa load.
    ///
    /// Chỉ **gán** giá trị, việc `save()` thuộc `BookTransactionCoordinator.refreshTitleTranslations`
    /// (từ 1.3.334 tầng View không còn tự save nữa). Trả `true` khi có field thực sự đổi để caller
    /// khỏi mở transaction rỗng.
    @discardableResult
    public static func refreshTranslations(for book: Book, in config: TranslationConfigSnapshot? = nil) -> Bool {
        guard TranslationManager.shared.isVietPhraseLoaded else { return false }
        return assignSearchTranslations(to: book, in: config, onlyEmpty: false)
    }

    /// Gán hai cột theo `searchTranslations`; `onlyEmpty` ⇒ chỉ cột còn rỗng (backfill). Tên / tác giả gốc rỗng thì bỏ qua
    /// (dịch ra vẫn rỗng). Trả `true` khi có cột đổi.
    @discardableResult
    static func assignSearchTranslations(to book: Book, in config: TranslationConfigSnapshot?, onlyEmpty: Bool) -> Bool {
        let fillsTitle = !book.title.isEmpty && (!onlyEmpty || book.titleTrans.isEmpty)
        let fillsAuthor = !book.author.isEmpty && (!onlyEmpty || book.authorTrans.isEmpty)
        guard fillsTitle || fillsAuthor else { return false }
        let values = searchTranslations(
            title: book.title,
            author: book.author,
            bookId: book.bookId,
            packageId: book.extensionPackageId,
            in: config
        )
        var didChange = false
        if fillsTitle, !values.title.isEmpty, values.title != book.titleTrans {
            book.titleTrans = values.title
            didChange = true
        }
        if fillsAuthor, !values.author.isEmpty, values.author != book.authorTrans {
            book.authorTrans = values.author
            didChange = true
        }
        return didChange
    }
}
