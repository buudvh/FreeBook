import XCTest
import SwiftData
@testable import FreeBook

@MainActor
final class ChapterContentRepositoryTests: XCTestCase {
    func testPersistentContentIsUsedEvenWhenCachedFlagIsFalse() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = makeBook(bookId: "local-first-book")
        let chapter = Chapter(
            id: "local-first-book_chapter-0",
            title: "Chapter 1",
            url: "chapter-0",
            index: 0,
            content: " First line \n\n Second line ",
            isCached: false
        )
        chapter.book = book
        book.chapters = [chapter]
        context.insert(book)
        try context.save()

        let repository = ChapterContentRepository()
        await repository.configure(container: container)
        let result = try await repository.load(
            ChapterContentRequest(
                bookId: book.bookId,
                chapterIndex: 0,
                title: chapter.title,
                url: chapter.url,
                host: nil,
                bookMetadata: nil,
                extensionInfo: nil,
                forceRefresh: false
            )
        )

        XCTAssertEqual(result.origin, .persistentCache)
        XCTAssertEqual(result.document.text.content, "First line\nSecond line")

        let verificationContext = ModelContext(container)
        let storedBooks = try verificationContext.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(storedBooks.first?.chapters.first?.isCached, true)
    }

    func testBackgroundUpsertCreatesMissingBookAndChapter() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let chapter = ChapterMetadataSnapshot(
            title: "Chapter 1",
            url: "chapter-1",
            index: 0,
            host: "https://example.com"
        )
        let book = BookMetadataSnapshot(
            bookId: "new-online-book",
            title: "Online Book",
            author: "Author",
            coverUrl: "",
            desc: "",
            detailUrl: "https://example.com/book",
            sourceName: "Test",
            sourceUrl: "https://example.com",
            extensionPackageId: "test-extension",
            host: "https://example.com",
            chapters: [chapter]
        )

        await store.enqueueWrite(
            key: "new-online-book|0|chapter-1",
            bookId: book.bookId,
            book: book,
            chapter: chapter,
            content: "Content"
        )
        await store.flush(bookId: book.bookId)

        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        let persistedBook = try XCTUnwrap(books.first(where: { $0.bookId == book.bookId }))
        let persistedChapter = try XCTUnwrap(persistedBook.chapters.first)
        XCTAssertEqual(persistedChapter.content, "Content")
        XCTAssertTrue(persistedChapter.isCached)
        XCTAssertTrue(persistedBook.isHistory)
    }

    func testRepositoryMemorySurvivesReaderScopedCacheLifetime() async throws {
        let repository = ChapterContentRepository()
        let document = ChapterDocument(
            chapterIndex: 2,
            title: "Chapter 3",
            url: "chapter-3",
            host: nil,
            text: ChapterTextNormalizer.normalize("Cached in shared memory")
        )
        await repository.store(document, bookId: "memory-book")

        let result = try await repository.load(
            ChapterContentRequest(
                bookId: "memory-book",
                chapterIndex: 2,
                title: document.title,
                url: document.url,
                host: nil,
                bookMetadata: nil,
                extensionInfo: nil,
                forceRefresh: false
            )
        )

        XCTAssertEqual(result.origin, .memory)
        XCTAssertEqual(result.document, document)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Book.self,
            Chapter.self,
            configurations: configuration
        )
    }

    private func makeBook(bookId: String) -> Book {
        Book(
            bookId: bookId,
            title: "Test Book",
            author: "Author",
            coverUrl: "",
            desc: "",
            detailUrl: "https://example.com/book",
            sourceName: "Test",
            sourceUrl: "https://example.com",
            extensionPackageId: "test-extension"
        )
    }
}
