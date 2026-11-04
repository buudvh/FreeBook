import Foundation
import SwiftData

/// Gắn lại nguồn cho truyện mà tiện ích nguồn đã gỡ: đổi sang tiện ích đã cài có `regexp` khớp link chi tiết, **giữ
/// nguyên** `bookId`. Chương đã tải, tiến độ, Name/từ điển riêng và phiên AI đều theo `bookId` nên không phải chép như
/// lượt Đổi nguồn (`BookSourceChangeCoordinator`). Chi tiết truyện và lượt Đổi nguồn tìm truyện có sẵn theo cặp
/// (`extensionPackageId`, `detailUrl`), nên sau khi gắn lại, mở truyện từ nguồn mới vẫn ra đúng truyện này.
///
/// Caller (`MissingSourceRebindCoordinator`) đã kiểm mục lục nguồn mới cùng dạng link chương trước khi gọi.
extension BookTransactionCoordinator {
    /// - Returns: `.success(false)` khi truyện đã không còn ở nguồn `expectedOldPackageId` (vừa được đổi nguồn ở chỗ
    ///   khác trong lúc kiểm mục lục) — không ghi đè.
    @discardableResult
    public func rebindSource(
        bookId: String,
        expectedOldPackageId: String,
        packageId: String,
        sourceName: String,
        sourceUrl: String,
        host: String,
        in context: ModelContext
    ) -> Result<Bool, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        guard book.extensionPackageId == expectedOldPackageId else { return .success(false) }
        book.extensionPackageId = packageId
        book.sourceName = sourceName
        book.sourceUrl = sourceUrl
        book.host = host
        do {
            try context.save()
            return .success(true)
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
