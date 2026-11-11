import Foundation
import SwiftData

/// Ghi `titleTrans` / `authorTrans` trên `ModelContext` **riêng** (không chạm context của MainActor). Công thức ở
/// `BookTitleTranslationMigrator.searchTranslations` (phồn → giản của truyện rồi dịch, 1.3.846).
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

        let config = TranslationConfigStore.shared.snapshot()
        for (index, book) in pending.enumerated() {
            BookTitleTranslationMigrator.assignSearchTranslations(to: book, in: config, onlyEmpty: true)
            if (index + 1) % Self.batchSize == 0, context.hasChanges {
                try? context.save()
            }
        }
        if context.hasChanges { try? context.save() }

        AppLogger.shared.log("✅ [BookTitleTranslationMigrator] Đã backfill tên dịch/phương âm cho \(pending.count) sách")
    }

    /// Tính lại hai cột (kể cả cột đã có) cho truyện trong `bookIds`; `nil` ⇒ mọi truyện **đang bật** phồn → giản (lượt một
    /// lần sau 1.3.846). Một bản chụp cấu hình cho cả lượt. Trả `false` khi không đọc / lưu được (caller không ghi cờ).
    @discardableResult
    func refresh(bookIds: Set<String>?) async -> Bool {
        let context = ModelContext(container)
        let books: [Book]
        do {
            books = try context.fetch(FetchDescriptor<Book>())
        } catch {
            AppLogger.shared.log("❌ [BookTitleTranslationMigrator] Lỗi fetch sách để tính lại tên dịch: \(error.localizedDescription)")
            return false
        }
        let config = TranslationConfigStore.shared.snapshot()
        let targets = books.filter { book in
            if let bookIds { return bookIds.contains(book.bookId) }
            return config.convertsTraditional(bookId: book.bookId, packageId: book.extensionPackageId)
        }
        guard !targets.isEmpty else { return true }

        var changed = 0
        do {
            for (index, book) in targets.enumerated() {
                if BookTitleTranslationMigrator.assignSearchTranslations(to: book, in: config, onlyEmpty: false) {
                    changed += 1
                }
                if (index + 1) % Self.batchSize == 0, context.hasChanges {
                    try context.save()
                }
            }
            if context.hasChanges { try context.save() }
        } catch {
            AppLogger.shared.log("❌ [BookTitleTranslationMigrator] Lỗi lưu tên dịch sau khi đổi phồn→giản: \(error.localizedDescription)")
            return false
        }
        AppLogger.shared.log("📚 [BookTitleTranslationMigrator] Tính lại tên dịch/phiên âm theo phồn→giản: \(changed)/\(targets.count) truyện đổi")
        return true
    }
}
