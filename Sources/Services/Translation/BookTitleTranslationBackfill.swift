import Foundation
import SwiftData

internal actor BookTitleTranslationBackfill {
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
