import Foundation
import SwiftData

internal actor BookTitleTranslationBackfill {
    /// Số sách xử lý mỗi lần `save()` để tránh giữ transaction quá lớn.
    private static let batchSize = 50

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

        // Chỉ sách còn trường gốc khác rỗng để dịch: tên/tác giả rỗng dịch ra vẫn rỗng, nếu không lọc
        // thì sách đó bị coi là "pending" và gây save ở mọi lần khởi động.
        let pending = books.filter {
            ($0.titleTrans.isEmpty && !$0.title.isEmpty) || ($0.authorTrans.isEmpty && !$0.author.isEmpty)
        }
        guard !pending.isEmpty else { return }

        for (index, book) in pending.enumerated() {
            if book.titleTrans.isEmpty, !book.title.isEmpty {
                let translated = TranslateUtils.translateMeta(book.title, bookId: book.bookId)
                if !translated.isEmpty, translated != book.titleTrans { book.titleTrans = translated }
            }
            if book.authorTrans.isEmpty, !book.author.isEmpty {
                let translated = TranslateUtils.translateAuthorHanViet(book.author)
                if !translated.isEmpty, translated != book.authorTrans { book.authorTrans = translated }
            }
            if (index + 1) % Self.batchSize == 0, context.hasChanges {
                try? context.save()
            }
        }
        if context.hasChanges { try? context.save() }

        AppLogger.shared.log("✅ [BookTitleTranslationMigrator] Đã backfill tên dịch/phương âm cho \(pending.count) sách")
    }
}
