import XCTest
@testable import FreeBook

final class ReaderRouteTests: XCTestCase {
    func testBookDetailReaderRoute_keepsChapterIndexAsIdentity() {
        let route = ReaderRoute(chapterIndex: 37)

        XCTAssertEqual(route.chapterIndex, 37)
        XCTAssertEqual(route.id, 37)
        XCTAssertEqual(route, ReaderRoute(chapterIndex: 37))
        XCTAssertNotEqual(route, ReaderRoute(chapterIndex: 3))
    }

    func testShelfReaderRoute_identityChangesWhenBookOrChapterChanges() {
        let routeA1 = ShelfReaderRoute(
            bookId: "bookA",
            extensionPackageId: "pkg1",
            chapterIndex: 5,
            paragraphIndex: 2,
            detailUrl: "http://example.com/a",
            sourceName: "Source A"
        )
        let routeA2 = ShelfReaderRoute(
            bookId: "bookA",
            extensionPackageId: "pkg1",
            chapterIndex: 5,
            paragraphIndex: 2,
            detailUrl: "http://example.com/a",
            sourceName: "Source A"
        )
        let routeA3DifferentChapter = ShelfReaderRoute(
            bookId: "bookA",
            extensionPackageId: "pkg1",
            chapterIndex: 6,
            paragraphIndex: 2,
            detailUrl: "http://example.com/a",
            sourceName: "Source A"
        )
        let routeB = ShelfReaderRoute(
            bookId: "bookB",
            extensionPackageId: "pkg1",
            chapterIndex: 5,
            paragraphIndex: 2,
            detailUrl: "http://example.com/b",
            sourceName: "Source B"
        )

        XCTAssertEqual(routeA1.id, "bookA_5_2")
        XCTAssertEqual(routeA1, routeA2)
        XCTAssertNotEqual(routeA1, routeB)
        XCTAssertNotEqual(routeA1.id, routeB.id)

        // Same book, different chapter index
        XCTAssertNotEqual(routeA1, routeA3DifferentChapter)
        XCTAssertNotEqual(routeA1.id, routeA3DifferentChapter.id)
    }

    func testShelfReaderRoute_distinctIdsForDifferentParagraphs() {
        let route1 = ShelfReaderRoute(
            bookId: "bookA",
            extensionPackageId: "pkg1",
            chapterIndex: 0,
            paragraphIndex: 0,
            detailUrl: "http://example.com/a",
            sourceName: "Source A"
        )
        let route2 = ShelfReaderRoute(
            bookId: "bookA",
            extensionPackageId: "pkg1",
            chapterIndex: 0,
            paragraphIndex: 10,
            detailUrl: "http://example.com/a",
            sourceName: "Source A"
        )

        XCTAssertNotEqual(route1.id, route2.id)
    }
}
