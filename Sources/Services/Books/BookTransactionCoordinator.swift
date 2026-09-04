import Foundation
import SwiftData

@MainActor
public final class BookTransactionCoordinator {
    public static let shared = BookTransactionCoordinator()

    private init() {}

    @discardableResult
    public func addBookToShelf(command: AddBookToShelfCommand, in context: ModelContext) -> Result<Book, Error> {
        let bookId = command.bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1

        let book: Book
        if let existing = try? context.fetch(descriptor).first {
            book = existing
            book.title = command.title
            book.author = command.author
            book.coverUrl = command.coverUrl
            book.desc = command.desc
            book.detailUrl = command.detailUrl
            book.sourceName = command.sourceName
            book.sourceUrl = command.sourceUrl
            book.extensionPackageId = command.extensionPackageId
            if let h = command.host { book.host = h }
            book.isOnShelf = command.isOnShelf
            book.isHistory = command.isHistory
            book.lastReadDate = command.lastReadDate ?? Date()
            if !command.isOnShelf {
                // Truyện tụt khỏi kệ (đổi nguồn, khôi phục backup…) thì không được giữ bộ sưu tập cũ.
                book.collections = []
                book.isPinned = false
            }
        } else {
            book = Book(
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
            context.insert(book)
        }

        do {
            try context.save()
            return .success(book)
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func updateBookMetadata(
        bookId: String,
        title: String,
        author: String,
        coverUrl: String,
        desc: String,
        host: String,
        in context: ModelContext
    ) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.title = title
        book.author = author
        book.coverUrl = coverUrl
        book.desc = desc
        book.host = host
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Người dùng tự sửa thông tin truyện. Tính lại luôn `titleTrans`/`authorTrans` theo đúng công thức
    /// của `BookTitleTranslationBackfill`, vì kệ sách đọc hai field đó chứ không dịch lại tại chỗ.
    @discardableResult
    public func updateBookInfo(command: EditBookInfoCommand, in context: ModelContext) -> Result<Void, Error> {
        let bookId = command.bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.title = command.title
        book.author = command.author
        book.coverUrl = command.coverUrl
        book.titleTrans = TranslateUtils.translateMeta(command.title, bookId: bookId)
        book.authorTrans = TranslateUtils.translateAuthorHanViet(command.author)
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Làm mới `titleTrans`/`authorTrans` lúc mở truyện (Reader / màn Chi tiết).
    ///
    /// Trước 1.3.334 hai màn đó tự gọi `BookTitleTranslationMigrator.refreshTranslations` rồi
    /// `try? modelContext.save()` — ghi SwiftData ngay trong tầng View, đúng cái luật
    /// `VIEW_SWIFTDATA_MUTATION` cấm. Giờ transaction thuộc coordinator, còn công thức dịch vẫn ở
    /// migrator. Trả `.success(false)` khi không có gì đổi (không mở transaction rỗng).
    @discardableResult
    public func refreshTitleTranslations(bookId: String, in context: ModelContext) -> Result<Bool, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        guard BookTitleTranslationMigrator.refreshTranslations(for: book) else {
            return .success(false)
        }
        do {
            try context.save()
            return .success(true)
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func setOnShelf(bookId: String, isOnShelf: Bool, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.isOnShelf = isOnShelf
        book.isHistory = false
        book.lastReadDate = Date()
        // Giữ bất biến "trong bộ sưu tập ⇒ ở trên kệ" kể cả khi có caller hạ cờ qua hàm này.
        if !isOnShelf {
            book.collections = []
            book.isPinned = false
        }
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func removeFromShelf(bookId: String, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.isOnShelf = false
        book.isHistory = true
        book.lastReadDate = Date()
        // Bất biến "truyện trong bộ sưu tập luôn ở trên kệ": rời kệ là rời hết bộ sưu tập. Không xoá
        // `BookCollection` nào — chỉ tháo liên kết.
        book.collections = []
        book.isPinned = false
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Ghim/bỏ ghim truyện lên đầu kệ. Cùng khuôn với `ExtensionTransactionCoordinator.togglePinned`.
    @discardableResult
    public func setPinned(bookId: String, isPinned: Bool, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.isPinned = isPinned
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func setCurrentChapterIndex(bookId: String, index: Int, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.currentChapterIndex = index
        book.lastReadDate = Date()
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Bỏ truyện khỏi danh sách Lịch sử mà vẫn giữ trên kệ. Trước 1.3.328 `ShelfView` gán thẳng
    /// `book.isHistory` rồi `modelContext.save()` — vi phạm luật View-SwiftData, giờ đi qua đây.
    @discardableResult
    public func setHistory(bookId: String, isHistory: Bool, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        book.isHistory = isHistory
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func deleteBook(bookId: String, in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        if let book = try? context.fetch(descriptor).first {
            context.delete(book)
            do {
                try context.save()
                return .success(())
            } catch {
                return .failure(BookTransactionError.saveFailed(error.localizedDescription))
            }
        }
        return .success(())
    }

    @discardableResult
    public func insertChapterDTO(
        bookId: String,
        title: String,
        url: String,
        index: Int,
        isCached: Bool = false,
        offset: Int64 = 0,
        length: Int64 = 0,
        titleTrans: String? = nil,
        in context: ModelContext
    ) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        let chapId = Chapter.generateId(bookId: bookId, url: url, index: index)
        let chapter = Chapter(
            id: chapId,
            bookId: bookId,
            title: title,
            url: url,
            index: index,
            isCached: isCached,
            offset: offset,
            length: length,
            titleTrans: titleTrans
        )
        chapter.book = book
        context.insert(chapter)
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }

    @discardableResult
    public func updateChapterTitleTranslations(bookId: String, translations: [String: String], in context: ModelContext) -> Result<Void, Error> {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        guard let book = try? context.fetch(descriptor).first else {
            return .failure(BookTransactionError.bookNotFound(bookId))
        }
        for chap in book.chapters {
            if let trans = translations[chap.id] {
                chap.titleTrans = trans
            }
        }
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(BookTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
