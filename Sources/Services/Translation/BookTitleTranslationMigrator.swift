import Foundation
import SwiftData

/// Backfill `titleTrans`/`authorTrans` cho những sách còn để trống.
///
/// Chạy mỗi lần mở app sau khi từ điển đã nạp xong (mirror pattern nạp dict ban đầu
/// trong `TranslationManager.init`). Chỉ xử lý sách còn rỗng nên lần đầu chạy hết,
/// các lần sau no-op. Hai cột này phục vụ tìm kiếm và không phụ thuộc trạng thái
/// toggle dịch (luôn lưu tên đã dịch/phương âm để search bất kể bật/tắt).
public enum BookTitleTranslationMigrator {
    fileprivate static let batchSize = 50

    public static func runIfNeeded(container: ModelContainer) async {
        // Chỉ dịch được khi từ điển VietPhrase đã sẵn sàng; nếu chưa thì bỏ qua,
        // lần mở app kế tiếp sẽ chạy lại.
        guard TranslationManager.shared.isVietPhraseLoaded else { return }

        await BookTitleTranslationBackfill(container: container).backfill()
    }

    /// Cập nhật lại `titleTrans`/`authorTrans` cho một cuốn sách ngay khi mở từ
    /// Kệ sách / màn hình chi tiết — không chờ migration lần mở app kế tiếp.
    /// Chỉ ghi khi giá trị thay đổi (tránh save thừa); bỏ qua nếu từ điển chưa load.
    /// Caller phải tự `modelContext.save()` sau khi gọi.
    public static func refreshTranslations(for book: Book) {
        guard TranslationManager.shared.isVietPhraseLoaded else { return }

        if !book.title.isEmpty {
            let translated = TranslateUtils.translateMeta(book.title, bookId: book.bookId)
            if translated != book.titleTrans {
                book.titleTrans = translated
            }
        }
        if !book.author.isEmpty {
            let translated = TranslateUtils.translateAuthorHanViet(book.author)
            if translated != book.authorTrans {
                book.authorTrans = translated
            }
        }
    }
}

private actor BookTitleTranslationBackfill {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

    func backfill() async {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Book>()
        let books: [Book]
        do {
            books = try context.fetch(descriptor)
        } catch {
            AppLogger.shared.log("❌ [BookTitleTranslationMigrator] Lỗi fetch sách: \(error.localizedDescription)")
            return
        }

        let pending = books.filter { $0.titleTrans.isEmpty || $0.authorTrans.isEmpty }
        guard !pending.isEmpty else { return }

        for (index, book) in pending.enumerated() {
            if book.titleTrans.isEmpty {
                book.titleTrans = TranslateUtils.translateMeta(book.title, bookId: book.bookId)
            }
            if book.authorTrans.isEmpty {
                book.authorTrans = TranslateUtils.translateAuthorHanViet(book.author)
            }
            if (index + 1) % BookTitleTranslationMigrator.batchSize == 0 {
                try? context.save()
            }
        }
        try? context.save()

        AppLogger.shared.log("✅ [BookTitleTranslationMigrator] Đã backfill tên dịch/phương âm cho \(pending.count) sách")
    }
}
