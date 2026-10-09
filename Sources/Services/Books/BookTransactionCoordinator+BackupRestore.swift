import Foundation
import SwiftData

/// Đường ghi theo lô cho lượt khôi phục backup.
///
/// Đi từng truyện qua `addBookToShelf` → `setPinned` → `updateBookInfo` là 2–3 lần `save()` mỗi truyện,
/// và trước đây cả danh sách chạy trong **một** job MainActor: khôi phục vài trăm truyện mới làm đơ UI.
/// Hàm dưới dựng đúng các giá trị ba hàm kia đặt cho một truyện **mới**, nhưng chạy trên context nền
/// của caller và chỉ `save()` một lần cho cả lô.
extension BookTransactionCoordinator {
    /// Thêm một lô truyện mới từ backup rồi `save()` một lần.
    ///
    /// `nonisolated static`: coordinator không giữ trạng thái, còn `shared` thuộc MainActor nên worker
    /// nền không chạm được — hàm chỉ dùng `context` do caller truyền vào.
    ///
    /// - Parameters:
    ///   - items: truyện **chưa có** trong thư viện, `bookId` không trùng nhau (caller tự lọc).
    ///     `isPinned` đã được caller tính sẵn (`record.isPinned == true && record.isOnShelf`).
    ///   - context: `ModelContext` riêng do caller tạo từ `ModelContainer`, không phải context của View.
    /// - Returns: `.failure` thì context đã `rollback()` — không truyện nào của lô được ghi; caller chạy
    ///   lại lô qua đường từng truyện để lỗi vẫn được báo theo truyện.
    nonisolated static func addBooksFromBackup(
        _ items: [(command: AddBookToShelfCommand, isPinned: Bool)],
        in context: ModelContext
    ) -> Result<Void, Error> {
        guard !items.isEmpty else { return .success(()) }

        for item in items {
            let command = item.command
            // Cùng giá trị nhánh "truyện mới" của `addBookToShelf`.
            let book = Book(
                bookId: command.bookId,
                title: command.title,
                author: command.author,
                coverUrl: command.coverUrl,
                desc: command.desc,
                detailUrl: command.detailUrl,
                sourceName: command.sourceName,
                sourceUrl: command.sourceUrl,
                extensionPackageId: command.extensionPackageId,
                currentChapterIndex: command.currentChapterIndex,
                currentChapterPage: command.currentChapterPage,
                currentChapterTitle: command.currentChapterTitle,
                isOnShelf: command.isOnShelf,
                isHistory: command.isHistory,
                host: command.host
            )
            book.lastReadDate = command.lastReadDate ?? Date()
            // Cùng việc `setPinned(isPinned: true)` của đường từng truyện.
            if item.isPinned { book.isPinned = true }
            // Cùng công thức `updateBookInfo`: kệ sách đọc hai field này chứ không dịch lại tại chỗ.
            book.titleTrans = TranslateUtils.translateMeta(command.title, bookId: command.bookId)
            book.authorTrans = TranslateUtils.translateAuthorHanViet(command.author)
            context.insert(book)
        }

        do {
            try context.save()
            return .success(())
        } catch {
            context.rollback()
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
