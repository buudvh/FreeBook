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
