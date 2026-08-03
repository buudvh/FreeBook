import XCTest
@testable import FreeBook

final class BookIdUtilsTests: XCTestCase {
    func testMake_withPackageIdAndUrl_returnsExactSha256LiteralHash() {
        let packageId = "sangtacviet"
        let detailUrl = "https://example.com/book/1"
        // Raw key: "sangtacviet|https://example.com/book/1"
        // SHA-256 hex: 8f7be8aa65ddb87cdfb08f5195e3474d275e523f6630f9a936a5fae56db6c7b9
        // First 16 hex chars: 8f7be8aa65ddb87c
        let expectedId = "sangtacviet_8f7be8aa65ddb87c"

        let result = BookIdUtils.make(extensionPackageId: packageId, detailUrl: detailUrl)
        XCTAssertEqual(result, expectedId)
    }

    func testMake_withWhitespaceAndUppercase_normalizesInput() {
        let idUnnormalized = BookIdUtils.make(extensionPackageId: "  SangTacViet  ", detailUrl: "  https://example.com/book/1  ")
        let expectedId = "sangtacviet_8f7be8aa65ddb87c"
        
        XCTAssertEqual(idUnnormalized, expectedId)
    }

    func testMake_withEmptyInputs_returnsEmptyString() {
        let id = BookIdUtils.make(extensionPackageId: "", detailUrl: "")
        XCTAssertEqual(id, "")
    }

    func testMake_identicalInputs_returnsIdenticalHash() {
        let id1 = BookIdUtils.make(extensionPackageId: "tangthuvien", detailUrl: "https://tangthuvien.vn/doc-truyen/test")
        let id2 = BookIdUtils.make(extensionPackageId: "tangthuvien", detailUrl: "https://tangthuvien.vn/doc-truyen/test")
        XCTAssertEqual(id1, id2)
    }
}
