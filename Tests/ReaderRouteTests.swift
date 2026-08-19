import XCTest
@testable import FreeBook

final class ReaderRouteTests: XCTestCase {
    private func makeRoute(
        bookId: String = "bookA",
        chapterIndex: Int = 5,
        paragraphIndex: Int? = nil
    ) -> ReaderRouterRoute {
        ReaderRouterRoute(
            bookId: bookId,
            extensionPackageId: "pkg1",
            chapterIndex: chapterIndex,
            onlineChapters: [],
            bookTitle: nil,
            bookAuthor: nil,
            bookCoverUrl: nil,
            bookDesc: nil,
            bookDetailUrl: "http://example.com/a",
            bookSourceName: "Source A",
            initialParagraphIndex: paragraphIndex
        )
    }

    func testReaderRouterRoute_idChangesWhenBookOrChapterChanges() {
        let routeA1 = makeRoute()
        let routeA3DifferentChapter = makeRoute(chapterIndex: 6)
        let routeB = makeRoute(bookId: "bookB")

        XCTAssertEqual(routeA1.id, "bookA_5")
        XCTAssertNotEqual(routeA1.id, routeB.id)

        // Same book, different chapter index
        XCTAssertNotEqual(routeA1.id, routeA3DifferentChapter.id)
    }
}
