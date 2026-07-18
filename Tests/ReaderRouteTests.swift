import XCTest
@testable import FreeBook

final class ReaderRouteTests: XCTestCase {
    func testRouteKeepsOriginalChapterIndexAsIdentity() {
        let route = ReaderRoute(chapterIndex: 37)

        XCTAssertEqual(route.chapterIndex, 37)
        XCTAssertEqual(route.id, 37)
        XCTAssertEqual(route, ReaderRoute(chapterIndex: 37))
        XCTAssertNotEqual(route, ReaderRoute(chapterIndex: 3))
    }
}
