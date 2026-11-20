import Foundation
import SwiftData

/// Lệnh ghi **nhiều truyện một lần lưu** cho chế độ chọn nhiều của Kệ Sách / Lịch Sử (`ShelfView+Selection`). Mỗi hàm chép
/// đúng luật của bản một truyện cùng tên ở `BookTransactionCoordinator.swift` — sửa luật ở bên nào thì sửa cả bên kia.
///
/// Lọc truyện trên RAM (fetch hết rồi `filter`), không dùng predicate `contains` trên chuỗi: bộ dịch predicate sang
/// SQLite của SwiftData iOS 17 lỗi với kiểu lọc này.
extension BookTransactionCoordinator {
    /// Bỏ nhiều truyện khỏi kệ (về Lịch sử) — luật như `removeFromShelf(bookId:in:)`: tiện ích tắt "Lưu lịch sử"
    /// (`ExtensionHistoryPolicy`) thì không ghi mới vào Lịch sử; rời kệ là rời mọi bộ sưu tập + bỏ ghim (bất biến "trong bộ
    /// sưu tập ⇒ ở trên kệ"). Trả số truyện đã bỏ.
    @discardableResult
    public func removeFromShelf(bookIds: [String], in context: ModelContext) -> Result<Int, Error> {
        let books = batchBooks(bookIds, in: context)
        guard !books.isEmpty else { return .success(0) }
        let now = Date()
        for book in books {
            book.isOnShelf = false
            if ExtensionHistoryPolicy.recordsHistory(packageId: book.extensionPackageId) {
                book.isHistory = true
            }
            book.lastReadDate = now
            book.collections = []
            book.isPinned = false
        }
        return saveBatch(context, count: books.count)
    }

    /// Đặt cờ Lịch sử cho nhiều truyện — như `setHistory(bookId:isHistory:in:)` (chỉ đổi cờ, không đụng kệ). Trả số
    /// truyện đã ghi.
    @discardableResult
    public func setHistory(bookIds: [String], isHistory: Bool, in context: ModelContext) -> Result<Int, Error> {
        let books = batchBooks(bookIds, in: context)
        guard !books.isEmpty else { return .success(0) }
        for book in books {
            book.isHistory = isHistory
        }
        return saveBatch(context, count: books.count)
    }

    private func batchBooks(_ bookIds: [String], in context: ModelContext) -> [Book] {
        let wanted = Set(bookIds)
        guard !wanted.isEmpty else { return [] }
        let all = (try? context.fetch(FetchDescriptor<Book>())) ?? []
        return all.filter { wanted.contains($0.bookId) }
    }

    private func saveBatch(_ context: ModelContext, count: Int) -> Result<Int, Error> {
        do {
            try context.save()
            return .success(count)
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
