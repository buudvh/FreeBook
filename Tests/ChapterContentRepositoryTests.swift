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

    func testSaveChapterListReplaceFullTOCPreservesCachedContentAndDeletesStale() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let context = ModelContext(container)
        let book = makeBook(bookId: "toc-test-book")

        let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: "toc-test-book", content: "Cached Content")
        let cachedChap = Chapter(
            id: "toc-test-book_chapter-0",
            bookId: "toc-test-book",
            title: "Old Title 1",
            url: "url-1",
            index: 0,
            isCached: true,
            offset: offset,
            length: length
        )
        let staleChap = Chapter(
            id: "toc-test-book_chapter-1",
            bookId: "toc-test-book",
            title: "Old Title 2",
            url: "url-2",
            index: 1
        )
        cachedChap.book = book
        staleChap.book = book
        book.chapters = [cachedChap, staleChap]
        context.insert(book)
        try context.save()

        let newSnapshots = [
            ChapterMetadataSnapshot(title: "New Title 1", url: "url-1", index: 0, host: nil),
            ChapterMetadataSnapshot(title: "New Title 3", url: "url-3", index: 1, host: nil)
        ]

        let result = try await store.saveChapterList(
            bookId: "toc-test-book",
            createSnapshot: nil,
            chapters: newSnapshots,
            mode: .replaceFullTOC
        )

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.updated, 1)
        XCTAssertEqual(result.deleted, 1)
        XCTAssertEqual(result.totalChapters, 2)

        let verifyContext = ModelContext(container)
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "toc-test-book" })
        descriptor.fetchLimit = 1
        let updatedBook = try XCTUnwrap(verifyContext.fetch(descriptor).first)

        XCTAssertEqual(updatedBook.chapters.count, 2)
        let verifyCached = try XCTUnwrap(updatedBook.chapters.first(where: { $0.url == "url-1" }))
        XCTAssertEqual(verifyCached.title, "New Title 1")
        XCTAssertTrue(verifyCached.isCached)
        XCTAssertEqual(verifyCached.offset, offset)
        XCTAssertEqual(verifyCached.length, length)

        XCTAssertNil(updatedBook.chapters.first(where: { $0.url == "url-2" }))
        XCTAssertNotNil(updatedBook.chapters.first(where: { $0.url == "url-3" }))
    }

    func testSaveChapterListUpsertPageDoesNotDeleteStale() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let context = ModelContext(container)
        let book = makeBook(bookId: "upsert-test-book")

        let existingChap = Chapter(
            id: "upsert-test-book_chap-0",
            bookId: "upsert-test-book",
            title: "Page 1 Chap",
            url: "p1-chap",
            index: 0
        )
        existingChap.book = book
        book.chapters = [existingChap]
        context.insert(book)
        try context.save()

        let page2Snapshots = [
            ChapterMetadataSnapshot(title: "Page 2 Chap", url: "p2-chap", index: 1, host: nil)
        ]

        let result = try await store.saveChapterList(
            bookId: "upsert-test-book",
            createSnapshot: nil,
            chapters: page2Snapshots,
            mode: .upsertPage
        )

        XCTAssertEqual(result.inserted, 1)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.totalChapters, 2)

        let verifyContext = ModelContext(container)
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "upsert-test-book" })
        descriptor.fetchLimit = 1
        let updatedBook = try XCTUnwrap(verifyContext.fetch(descriptor).first)
        XCTAssertEqual(updatedBook.chapters.count, 2)
    }

    func testSaveChapterListTTSActiveProtection() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let context = ModelContext(container)
        let book = makeBook(bookId: "tts-active-book")

        let chap1 = Chapter(
            id: "tts-active-book_0",
            bookId: "tts-active-book",
            title: "Playing Chap",
            url: "playing-url",
            index: 0
        )
        chap1.book = book
        book.chapters = [chap1]
        context.insert(book)
        try context.save()

        let protectedTTS = ProtectedTTSChapter(bookId: "tts-active-book", index: 0, url: "playing-url")

        let newTOC = [
            ChapterMetadataSnapshot(title: "Different Chap", url: "different-url", index: 1, host: nil)
        ]

        let result = try await store.saveChapterList(
            bookId: "tts-active-book",
            createSnapshot: nil,
            chapters: newTOC,
            mode: .replaceFullTOC,
            protectedTTSChapter: protectedTTS
        )

        XCTAssertEqual(result.deleted, 0)

        let verifyContext = ModelContext(container)
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "tts-active-book" })
        descriptor.fetchLimit = 1
        let updatedBook = try XCTUnwrap(verifyContext.fetch(descriptor).first)
        XCTAssertTrue(updatedBook.chapters.contains(where: { $0.url == "playing-url" }))
    }

    func testFetchBookScopeIsolation() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let context = ModelContext(container)

        let book1 = makeBook(bookId: "isolated-book-1")
        let book2 = makeBook(bookId: "isolated-book-2")
        context.insert(book1)
        context.insert(book2)
        try context.save()

        let snapshots = [
            ChapterMetadataSnapshot(title: "Book 1 Chap 1", url: "b1-c1", index: 0, host: nil)
        ]

        let result = try await store.saveChapterList(
            bookId: "isolated-book-1",
            createSnapshot: nil,
            chapters: snapshots,
            mode: .replaceFullTOC
        )

        XCTAssertEqual(result.totalChapters, 1)

        let verifyContext = ModelContext(container)
        var descriptor1 = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "isolated-book-1" })
        descriptor1.fetchLimit = 1
        let res1 = try XCTUnwrap(verifyContext.fetch(descriptor1).first)
        XCTAssertEqual(res1.chapters.count, 1)

        var descriptor2 = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "isolated-book-2" })
        descriptor2.fetchLimit = 1
        let res2 = try XCTUnwrap(verifyContext.fetch(descriptor2).first)
        XCTAssertEqual(res2.chapters.count, 0)
    }

    func testReconciliationUrlAndIndexFallbackMatching() async throws {
        let container = try makeContainer()
        let store = ChapterPersistenceStore(container: container)
        let context = ModelContext(container)
        let book = makeBook(bookId: "fallback-match-book")

        let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: "fallback-match-book", content: "Content")
        let chapByUrl = Chapter(
            id: "fallback-match-book_c0",
            bookId: "fallback-match-book",
            title: "Url Match Chap",
            url: "unique-url-abc",
            index: 0,
            isCached: true,
            offset: offset,
            length: length
        )
        chapByUrl.titleTrans = "Tên dịch cũ"
        let chapByIndex = Chapter(
            id: "fallback-match-book_c1",
            bookId: "fallback-match-book",
            title: "Index Match Chap",
            url: "",
            index: 1
        )
        chapByUrl.book = book
        chapByIndex.book = book
        book.chapters = [chapByUrl, chapByIndex]
        context.insert(book)
        try context.save()

        let snapshots = [
            ChapterMetadataSnapshot(title: "Updated Url Match", url: "unique-url-abc", index: 0, host: nil, titleTrans: "Tên dịch mới 1"),
            ChapterMetadataSnapshot(title: "Updated Index Match", url: "new-url-xyz", index: 1, host: nil, titleTrans: "Tên dịch mới 2")
        ]

        let result = try await store.saveChapterList(
            bookId: "fallback-match-book",
            createSnapshot: nil,
            chapters: snapshots,
            mode: .replaceFullTOC
        )

        XCTAssertEqual(result.updated, 2)
        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.deleted, 0)
        XCTAssertEqual(result.totalChapters, 2)

        let verifyContext = ModelContext(container)
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == "fallback-match-book" })
        descriptor.fetchLimit = 1
        let res = try XCTUnwrap(verifyContext.fetch(descriptor).first)
        let updatedC0 = try XCTUnwrap(res.chapters.first(where: { $0.index == 0 }))
        XCTAssertEqual(updatedC0.title, "Updated Url Match")
        XCTAssertEqual(updatedC0.titleTrans, "Tên dịch mới 1")
        XCTAssertTrue(updatedC0.isCached)
        XCTAssertEqual(updatedC0.offset, offset)

        let updatedC1 = try XCTUnwrap(res.chapters.first(where: { $0.index == 1 }))
        XCTAssertEqual(updatedC1.title, "Updated Index Match")
        XCTAssertEqual(updatedC1.titleTrans, "Tên dịch mới 2")
    }
}
