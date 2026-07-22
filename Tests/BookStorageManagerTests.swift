import XCTest
import SwiftData
@testable import FreeBook

@available(iOS 17.0, *)
final class BookStorageManagerTests: XCTestCase {

    override func tearDown() async throws {
        TTSManager.shared.stop()
        BookStorageManager.mockSaveError = nil
        BookStorageManager.mockFetchError = nil
    }

    @MainActor
    func testDeleteBookAsync_HardDeletesBookAndChapters() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: config)
        let context = container.mainContext

        let book = Book(
            bookId: "test-delete-book-1",
            title: "Test Hard Delete",
            author: "Author",
            coverUrl: "",
            desc: "Desc",
            detailUrl: "http://example.com/1",
            sourceName: "Source",
            sourceUrl: "http://example.com",
            extensionPackageId: "ext1",
            isOnShelf: true,
            isHistory: false
        )
        context.insert(book)

        let chapter1 = Chapter(id: "chap-1", bookId: "test-delete-book-1", title: "Chap 1", url: "http://example.com/1/c1", index: 0)
        let chapter2 = Chapter(id: "chap-2", bookId: "test-delete-book-1", title: "Chap 2", url: "http://example.com/1/c2", index: 1)
        book.chapters.append(chapter1)
        book.chapters.append(chapter2)
        context.insert(chapter1)
        context.insert(chapter2)
        try context.save()

        // Test deleting book
        try await BookStorageManager.shared.deleteBookAsync(bookId: "test-delete-book-1", container: container)

        let fetchedBooks = try context.fetch(FetchDescriptor<Book>())
        XCTAssertEqual(fetchedBooks.count, 0, "Book should be hard-deleted from SwiftData")

        let fetchedChapters = try context.fetch(FetchDescriptor<Chapter>())
        XCTAssertEqual(fetchedChapters.count, 0, "Chapters should be cascade deleted by SwiftData relationship")
    }

    @MainActor
    func testClearAllOffShelfHistoryAsync_PreservesShelfBooksAndPlayingBook() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Book.self, Chapter.self, configurations: config)
        let context = container.mainContext

        // 1. Sách trên kệ sách (phải được giữ nguyên)
        let shelfBook = Book(
            bookId: "shelf-book-id",
            title: "Sách trên kệ",
            author: "Author",
            coverUrl: "",
            desc: "Desc",
            detailUrl: "http://example.com/shelf",
            sourceName: "Source",
            sourceUrl: "http://example.com",
            extensionPackageId: "ext1",
            isOnShelf: true,
            isHistory: true
        )
        context.insert(shelfBook)

        // 2. Sách lịch sử không ở trên kệ (sẽ bị xóa)
        let historyBook = Book(
            bookId: "history-off-shelf-id",
            title: "Sách lịch sử",
            author: "Author",
            coverUrl: "",
            desc: "Desc",
            detailUrl: "http://example.com/history",
            sourceName: "Source",
            sourceUrl: "http://example.com",
            extensionPackageId: "ext1",
            isOnShelf: false,
            isHistory: true
        )
        context.insert(historyBook)

        // 3. Sách đang nghe TTS (dù không ở trên kệ cũng phải bảo vệ)
        let playingBook = Book(
            bookId: "playing-book-id",
            title: "Sách đang nghe TTS",
            author: "Author",
            coverUrl: "",
            desc: "Desc",
            detailUrl: "http://example.com/playing",
            sourceName: "Source",
            sourceUrl: "http://example.com",
            extensionPackageId: "ext1",
            isOnShelf: false,
            isHistory: true
        )
        context.insert(playingBook)
        try context.save()

        // Giả lập TTS đang phát playingBook
        TTSManager.shared.playingBookId = "playing-book-id"

        // Thực hiện xóa toàn bộ lịch sử
        try await BookStorageManager.shared.clearAllOffShelfHistoryAsync(container: container)

        let remainingBooks = try context.fetch(FetchDescriptor<Book>())
        let remainingIds = remainingBooks.map { $0.bookId }

        XCTAssertTrue(remainingIds.contains("shelf-book-id"), "Sách trên kệ (isOnShelf == true) phải được giữ nguyên")
        XCTAssertTrue(remainingIds.contains("playing-book-id"), "Sách đang phát TTS phải được giữ nguyên không xóa")
        XCTAssertFalse(remainingIds.contains("history-off-shelf-id"), "Sách lịch sử không ở trên kệ phải bị hard-delete")
    }
}
