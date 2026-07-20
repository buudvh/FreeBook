import XCTest
import SwiftData
@testable import FreeBook

@MainActor
final class ChapterContentRepositoryTests: XCTestCase {
    override func tearDown() async throws {
        try? await BookBinManager.shared.deleteBinFile(for: "local-first-book")
        try? await BookBinManager.shared.deleteBinFile(for: "new-online-book")
        try? await BookBinManager.shared.deleteBinFile(for: "memory-book")
    }

    func testPersistentContentIsUsedWhenCachedFlagIsTrue() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let book = makeBook(bookId: "local-first-book")

        let rawContent = " First line \n\n Second line "
        let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: "local-first-book", content: rawContent)

        let chapter = Chapter(
            id: "local-first-book_chapter-0",
            bookId: "local-first-book",
            title: "Chapter 1",
            url: "chapter-0",
            index: 0,
            isCached: true,
            offset: offset,
            length: length
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

        let content = try await BookBinManager.shared.readChapterContent(
            bookId: book.bookId,
            offset: persistedChapter.offset,
            length: persistedChapter.length
        )
        XCTAssertEqual(content, "Content")
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

    // Focused test: Identity Unicode/Delimiter and branch isolation
    func testIdentityUnicodeAndDelimiter() {
        let bookId = "book|id⭐"
        let url = "url/path|special⭐"
        let index = 1

        let id = Chapter.generateId(bookId: bookId, url: url, index: index)
        XCTAssertEqual(id, "8:book|id⭐|U:17:url/path|special⭐")

        // 1. Same book + empty URL + index 0 vs 1 => different IDs
        let idEmpty0 = Chapter.generateId(bookId: "mybook", url: "", index: 0)
        let idEmpty1 = Chapter.generateId(bookId: "mybook", url: "   ", index: 1)
        XCTAssertEqual(idEmpty0, "6:mybook|I:0")
        XCTAssertEqual(idEmpty1, "6:mybook|I:1")
        XCTAssertNotEqual(idEmpty0, idEmpty1)

        // 2. Whitespace-only URL uses index fallback
        let idWhitespace = Chapter.generateId(bookId: "mybook", url: "  \n  ", index: 5)
        XCTAssertEqual(idWhitespace, "6:mybook|I:5")

        // 3. URL branch and index branch cannot collide (e.g. URL is "I:1" vs index is 1)
        let idUrlBranch = Chapter.generateId(bookId: "mybook", url: "I:1", index: 0)
        let idIndexBranch = Chapter.generateId(bookId: "mybook", url: "", index: 1)
        XCTAssertEqual(idUrlBranch, "6:mybook|U:3:I:1")
        XCTAssertEqual(idIndexBranch, "6:mybook|I:1")
        XCTAssertNotEqual(idUrlBranch, idIndexBranch)

        // 4. Unicode/delimiter distinct pairs remain distinct
        let id1 = Chapter.generateId(bookId: "a|b", url: "c", index: 0)
        let id2 = Chapter.generateId(bookId: "a", url: "b|c", index: 0)
        XCTAssertNotEqual(id1, id2)
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
