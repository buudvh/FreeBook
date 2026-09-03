import Foundation
import SwiftData

/// Chủ transaction cho `BookCollection`. Mọi thao tác ghi bộ sưu tập đi qua đây — View chỉ `@Query`
/// để đọc, giống `BookTransactionCoordinator` / `ExtensionTransactionCoordinator`.
///
/// Hai bất biến được cưỡng chế ở tầng này, không phải ở View:
/// 1. Truyện nằm trong bộ sưu tập thì **bắt buộc ở trên kệ** — mọi hàm thêm truyện đều bật `isOnShelf`.
/// 2. Bỏ truyện khỏi bộ sưu tập / xoá bộ sưu tập **không bao giờ** xoá truyện khỏi kệ hay khỏi thiết bị.
@MainActor
public final class BookCollectionCoordinator {
    public static let shared = BookCollectionCoordinator()

    private init() {}

    // MARK: - CRUD bộ sưu tập

    /// Tạo bộ sưu tập mới, xếp xuống cuối danh sách. Trùng tên (không phân biệt hoa/thường) bị chặn để
    /// người dùng không nhìn hai hàng y hệt nhau mà không biết bỏ sách vào đâu.
    @discardableResult
    public func createCollection(name: String, in context: ModelContext) -> Result<BookCollection, Error> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(BookTransactionError.invalidCollectionName)
        }
        // Lọc trên RAM: predicate lọc chuỗi của SwiftData iOS 17 dịch sai sang SQLite.
        let existing = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        if existing.contains(where: { $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame }) {
            return .failure(BookTransactionError.duplicateCollectionName(trimmed))
        }
        let nextOrder = (existing.map { $0.sortOrder }.max() ?? -1) + 1
        let collection = BookCollection(name: trimmed, sortOrder: nextOrder)
        context.insert(collection)
        do {
            try context.save()
            return .success(collection)
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func renameCollection(collectionId: String, name: String, in context: ModelContext) -> Result<Void, Error> {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(BookTransactionError.invalidCollectionName)
        }
        let all = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        guard let collection = all.first(where: { $0.collectionId == collectionId }) else {
            return .failure(BookTransactionError.collectionNotFound(collectionId))
        }
        if all.contains(where: {
            $0.collectionId != collectionId && $0.name.compare(trimmed, options: .caseInsensitive) == .orderedSame
        }) {
            return .failure(BookTransactionError.duplicateCollectionName(trimmed))
        }
        collection.name = trimmed
        return save(context)
    }

    /// Xoá bộ sưu tập. `deleteRule: .nullify` của `BookCollection.books` lo phần tháo liên kết, truyện
    /// vẫn ở trên kệ nguyên vẹn. Dọn tay mảng `books` trước cho chắc, vì đây là chỗ dễ hiểu sai nhất.
    @discardableResult
    public func deleteCollection(collectionId: String, in context: ModelContext) -> Result<Void, Error> {
        let all = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        guard let collection = all.first(where: { $0.collectionId == collectionId }) else {
            return .failure(BookTransactionError.collectionNotFound(collectionId))
        }
        collection.books = []
        context.delete(collection)
        return save(context)
    }

    /// Ghi lại thứ tự người dùng vừa kéo-thả trong tab Bộ sưu tập.
    @discardableResult
    public func reorderCollections(orderedIds: [String], in context: ModelContext) -> Result<Void, Error> {
        let all = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        for (index, id) in orderedIds.enumerated() {
            all.first(where: { $0.collectionId == id })?.sortOrder = index
        }
        return save(context)
    }

    // MARK: - Thành viên

    @discardableResult
    public func addBook(bookId: String, toCollection collectionId: String, in context: ModelContext) -> Result<Void, Error> {
        guard let book = fetchBook(bookId, in: context) else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        let all = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        guard let collection = all.first(where: { $0.collectionId == collectionId }) else {
            return .failure(BookTransactionError.collectionNotFound(collectionId))
        }
        if !book.collections.contains(where: { $0.collectionId == collectionId }) {
            book.collections.append(collection)
        }
        promoteToShelf(book)
        return save(context)
    }

    /// Bỏ truyện khỏi một bộ sưu tập. **Không** đụng tới `isOnShelf` — đây là yêu cầu tường minh:
    /// rời bộ sưu tập không phải rời kệ sách.
    @discardableResult
    public func removeBook(bookId: String, fromCollection collectionId: String, in context: ModelContext) -> Result<Void, Error> {
        guard let book = fetchBook(bookId, in: context) else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.collections.removeAll { $0.collectionId == collectionId }
        return save(context)
    }

    /// Đặt lại toàn bộ danh sách bộ sưu tập của một truyện trong một lần ghi. Sheet nhấn-giữ dùng hàm
    /// này để một lần lưu là xong, thay vì bắn nhiều lệnh add/remove liên tiếp.
    @discardableResult
    public func setMemberships(bookId: String, collectionIds: Set<String>, in context: ModelContext) -> Result<Void, Error> {
        guard let book = fetchBook(bookId, in: context) else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        let all = (try? context.fetch(FetchDescriptor<BookCollection>())) ?? []
        book.collections = all.filter { collectionIds.contains($0.collectionId) }
        if !collectionIds.isEmpty {
            promoteToShelf(book)
        }
        return save(context)
    }

    // MARK: - Phụ trợ

    private func fetchBook(_ bookId: String, in context: ModelContext) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Truyện vào bộ sưu tập là lên kệ luôn: đây là bất biến của tính năng, không phải tiện tay.
    private func promoteToShelf(_ book: Book) {
        guard !book.isOnShelf else { return }
        book.isOnShelf = true
        book.isHistory = false
    }

    private func save(_ context: ModelContext) -> Result<Void, Error> {
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
