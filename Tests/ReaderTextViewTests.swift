import XCTest
import UIKit
@testable import FreeBook

struct LineLayoutSnapshot: Equatable {
    let glyphRange: NSRange
    let characterRange: NSRange
    let rect: CGRect
}

final class ReaderTextViewTextKitTests: XCTestCase {
    func testTextKitColorRunDoesNotAlterLineFragmentsOrUsedRect() {
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
        textStorage.addAttribute(.paragraphStyle, value: paragraphStyle, range: fullRange)
        
        // 1. Initial Unhighlighted state
        layoutManager.ensureLayout(for: textContainer)
        let initialUsedRect = layoutManager.usedRect(for: textContainer)
        let initialSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)
        
        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph initially")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must equal initial length")
        
        // 2. TTS Highlighted state (color run on first clause chunk)
        let highlightRange = NSRange(location: 0, length: 47) // "Tiền Đa Đa nghe xong liền lộ ra làm khó biểu lộ,"
        textStorage.addAttribute(.backgroundColor, value: UIColor(white: 1.0, alpha: 0.16), range: highlightRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.white, range: highlightRange)
        layoutManager.ensureLayout(for: textContainer)
        let highlightedUsedRect = layoutManager.usedRect(for: textContainer)
        let highlightedSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)
        
        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph while highlighted")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must remain unchanged while highlighted")
        
        // 3. Cleared highlight state
        textStorage.removeAttribute(.backgroundColor, range: highlightRange)
        textStorage.addAttribute(.foregroundColor, value: UIColor.black, range: highlightRange)
        layoutManager.ensureLayout(for: textContainer)
        let finalUsedRect = layoutManager.usedRect(for: textContainer)
        let finalSnapshots = captureLineLayoutSnapshots(in: layoutManager, container: textContainer)
        
        XCTAssertEqual(textStorage.string, sampleParagraph, "textStorage string must equal sampleParagraph after clearing highlight")
        XCTAssertEqual((textStorage.string as NSString).length, (sampleParagraph as NSString).length, "UTF-16 length must remain unchanged after clearing highlight")
        
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
