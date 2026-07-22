import XCTest
@testable import FreeBook

final class DisplayTextFormatterTests: XCTestCase {
    func testTitleCaseBasicVietnamese() {
        let input = "đấu phá thương khung"
        let output = DisplayTextFormatter.titleCase(input)
        XCTAssertEqual(output, "Đấu Phá Thương Khung")
    }

    func testTitleCaseUppercaseVietnamese() {
        let input = "ĐẤU PHÁ THƯƠNG KHUNG"
        let output = DisplayTextFormatter.titleCase(input)
        XCTAssertEqual(output, "Đấu Phá Thương Khung")
    }

    func testTitleCasePreservesAcronyms() {
        let input = "truyện AI hay nhất (VIP)"
        let output = DisplayTextFormatter.titleCase(input)
        XCTAssertEqual(output, "Truyện AI Hay Nhất (VIP)")
    }

    func testTitleCasePreservesIOSAndShortAcronyms() {
        let input = "đọc sách trên iOS cho TTS"
        let output = DisplayTextFormatter.titleCase(input)
        XCTAssertEqual(output, "Đọc Sách Trên iOS Cho TTS")
    }

    func testTitleCaseNilAndEmpty() {
        XCTAssertEqual(DisplayTextFormatter.titleCase(nil), "")
        XCTAssertNil(DisplayTextFormatter.titleCaseOrNil(nil))
        XCTAssertEqual(DisplayTextFormatter.titleCase("   "), "")
        XCTAssertNil(DisplayTextFormatter.titleCaseOrNil("   "))
    }

    func testTitleCaseNormalizesWhitespace() {
        let input = "  đấu   phá \n  thương  khung \t "
        let output = DisplayTextFormatter.titleCase(input)
        XCTAssertEqual(output, "Đấu Phá Thương Khung")
    }
}
