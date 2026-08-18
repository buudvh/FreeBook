import XCTest
import UIKit
@testable import FreeBook

final class WrappingLabelTests: XCTestCase {

    private func makeLabel(text: String, numberOfLines: Int, font: UIFont = .systemFont(ofSize: 14), width: CGFloat = 280) -> WrappingLabel {
        let label = WrappingLabel()
        label.font = font
        label.numberOfLines = numberOfLines
        label.text = text
        label.frame = CGRect(x: 0, y: 0, width: width, height: 2000)
        label.layoutSubviews()
        return label
    }

    func testUnlimitedLabelIntrinsicHeightReflectsWrappedTextAfterLayout() {
        let text = String(repeating: "Đây là một câu tiếng Việt khá dài dùng để kiểm tra việc xuống dòng của nhãn văn bản. ", count: 6)
        let label = makeLabel(text: text, numberOfLines: 0)

        XCTAssertEqual(label.preferredMaxLayoutWidth, 280, accuracy: 0.01, "preferredMaxLayoutWidth must sync with bounds width")
        XCTAssertGreaterThan(label.intrinsicContentSize.height, label.font.lineHeight, "unlimited label must wrap to multiple lines after layout")
    }

    func testFullHeightExceedsCollapsedHeightForLongText() {
        let text = String(repeating: "Một đoạn mô tả khá dài nhằm chắc chắn rằng nội dung vượt quá bốn dòng giới hạn khi thu gọn. ", count: 5)

        let collapsed = makeLabel(text: text, numberOfLines: 4)
        let full = makeLabel(text: text, numberOfLines: 0)

        XCTAssertGreaterThan(full.intrinsicContentSize.height, collapsed.intrinsicContentSize.height, "full height must exceed collapsed height so 'Xem thêm' condition becomes true")
    }

    func testFullHeightEqualsCollapsedHeightForShortText() {
        let text = "Một đoạn mô tả ngắn gọn không bị cắt."

        let collapsed = makeLabel(text: text, numberOfLines: 4)
        let full = makeLabel(text: text, numberOfLines: 0)

        XCTAssertEqual(full.intrinsicContentSize.height, collapsed.intrinsicContentSize.height, accuracy: 0.5, "short text must not be considered truncated")
    }

    func testCollapsedLabelHeightCapsAtLineLimit() {
        let text = String(repeating: "Chuỗi rất dài khiến số dòng thực tế vượt xa giới hạn hiển thị khi thu gọn. ", count: 8)

        let collapsed = makeLabel(text: text, numberOfLines: 3)
        let threeLines = collapsed.font.lineHeight * 3

        XCTAssertEqual(collapsed.intrinsicContentSize.height, threeLines, accuracy: 0.5, "collapsed label must cap at its line limit")
    }
}