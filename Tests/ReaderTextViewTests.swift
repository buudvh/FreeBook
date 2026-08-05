import XCTest
import UIKit
@testable import FreeBook

struct LineLayoutSnapshot: Equatable {
    let glyphRange: NSRange
    let characterRange: NSRange
    let rect: CGRect
}

final class ReaderTextViewTextKitTests: XCTestCase {
    func testTextKitTemporaryAttributesDoNotAlterLineFragmentsOrUsedRect() {
        let sampleParagraph = "Tiền Đa Đa nghe xong liền lộ ra làm khó biểu lộ, 【Ta làm là làm được, nhưng là có chút người không nhận a. Quay đầu ta dẫn người đi trong học viện nhìn một chút.】"
        let font = UIFont.systemFont(ofSize: 18)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .justified

        let textStorage = NSTextStorage(string: sampleParagraph)
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: CGSize(width: 320, height: .greatestFiniteMagnitude))
        textContainer.lineFragmentPadding = 0
        layoutManager.addTextContainer(textContainer)

        let fullRange = NSRange(location: 0, length: (sampleParagraph as NSString).length)
        textStorage.addAttribute(.font, value: font, range: fullRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.black, range: fullRange)
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)

        // 1. Initial Unhighlighted state
        layoutManager.ensureLayout(for: textContainer)
        let initialUsedRect = layoutManager.usedRect(for: textContainer)
        let initialSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)

        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph initially")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must equal initial length")
        let initialBgAttr = textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        XCTAssertNil(initialBgAttr, "textStorage must have no persistent backgroundColor attribute initially")
        let initialTempAttrs = layoutManager.temporaryAttributes(at: 0, effectiveRange: nil)
        XCTAssertNil(initialTempAttrs[.backgroundColor], "layoutManager must have no temporary backgroundColor initially")

        // 2. TTS Highlighted state (temporary attributes on first clause chunk)
        let highlightRange = NSRange(location: 0, length: 47) // "Tiền Đa Đa nghe xong liền lộ ra làm khó biểu lộ,"
        let highlightBgColor = UIColor(white: 1.0, alpha: 0.16)
        let highlightFgColor = UIColor.white
        layoutManager.addTemporaryAttributes([
            .backgroundColor: highlightBgColor,
            .foregroundColor: highlightFgColor
        ], forCharacterRange: highlightRange)

        layoutManager.ensureLayout(for: textContainer)
        let highlightedUsedRect = layoutManager.usedRect(for: textContainer)
        let highlightedSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)

        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph while highlighted")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must remain unchanged while highlighted")

        // Assert persistent textStorage attributes remain unchanged
        let persistentBgAttrDuringHighlight = textStorage.attribute(.backgroundColor, at: 0, effectiveRange: nil)
        XCTAssertNil(persistentBgAttrDuringHighlight, "persistent textStorage must remain free of backgroundColor attribute during highlight")
        let persistentFgAttrDuringHighlight = textStorage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        XCTAssertEqual(persistentFgAttrDuringHighlight, UIColor.black, "persistent textStorage foregroundColor must remain black")

        // Assert temporary attributes exist in intended range and not outside
        let tempAttrsInHighlight = layoutManager.temporaryAttributes(at: 0, effectiveRange: nil)
        XCTAssertNotNil(tempAttrsInHighlight[.backgroundColor], "temporary attributes must contain backgroundColor inside highlight range")
        let tempAttrsOutsideHighlight = layoutManager.temporaryAttributes(at: 50, effectiveRange: nil)
        XCTAssertNil(tempAttrsOutsideHighlight[.backgroundColor], "temporary attributes must NOT contain backgroundColor outside highlight range")

        // 3. Cleared highlight state (removing temporary attributes)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: highlightRange)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: highlightRange)

        layoutManager.ensureLayout(for: textContainer)
        let finalUsedRect = layoutManager.usedRect(for: textContainer)
        let finalSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)

        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph after clearing highlight")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must remain unchanged after clearing highlight")
        let clearedTempAttrs = layoutManager.temporaryAttributes(at: 0, effectiveRange: nil)
        XCTAssertNil(clearedTempAttrs[.backgroundColor], "temporary attributes must be removed after clearing highlight")

        // Assert Line Layout Snapshots equality
        XCTAssertEqual(initialSnapshots, highlightedSnapshots, "Initial line layout snapshots must equal highlighted snapshots")
        XCTAssertEqual(initialSnapshots, finalSnapshots, "Initial line layout snapshots must equal final snapshots")

        // Assert usedRect dimensions equality within accuracy
        XCTAssertEqual(initialUsedRect.width, highlightedUsedRect.width, accuracy: 0.5, "UsedRect width must match when highlighted")
        XCTAssertEqual(initialUsedRect.height, highlightedUsedRect.height, accuracy: 0.5, "UsedRect height must match when highlighted")
        XCTAssertEqual(initialUsedRect.width, finalUsedRect.width, accuracy: 0.5, "UsedRect width must match when cleared")
        XCTAssertEqual(initialUsedRect.height, finalUsedRect.height, accuracy: 0.5, "UsedRect height must match when cleared")
    }

    private func captureLineLayoutSnapshots(in layoutManager: NSLayoutManager, container: NSTextContainer) -> [LineLayoutSnapshot] {
        var snapshots: [LineLayoutSnapshot] = []
        var glyphIndex = 0
        while glyphIndex < layoutManager.numberOfGlyphs {
            var glyphRange = NSRange()
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            snapshots.append(LineLayoutSnapshot(glyphRange: glyphRange, characterRange: characterRange, rect: rect))
            glyphIndex = NSMaxRange(glyphRange)
        }
        return snapshots
    }
}
