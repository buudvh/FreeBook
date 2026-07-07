import XCTest
@testable import FreeBook

@MainActor
final class TTSManagerTests: XCTestCase {
    
    func testTextSegmentationUnderDefaultLength() {
        let manager = TTSManager.shared
        manager.chunkLength = 1000
        
        let sampleContent = """
        Đoạn văn thứ nhất ngắn.
        Đoạn văn thứ hai cũng ngắn.
        """
        
        let mockChapter = TTSChapterInfo(title: "Test Chapter", url: "test_url", index: 0, cachedContent: sampleContent)
        manager.startSpeaking(
            bookId: "test_book_id",
            chapters: [mockChapter],
            currentIndex: 0,
            chapterContent: sampleContent,
            startParagraphIndex: 0,
            bookTitle: "Test Book",
            extensionInfo: nil
        )
        
        XCTAssertEqual(manager.paragraphs.count, 2)
        XCTAssertEqual(manager.paragraphs.first?.text, "Đoạn văn thứ nhất ngắn.")
        
        manager.stop()
    }
    
    func testTextSegmentationOverDefaultLength() {
        let manager = TTSManager.shared
        manager.chunkLength = 20
        
        let sampleContent = "Đây là một câu rất dài vượt quá độ dài giới hạn hai mươi ký tự."
        
        let mockChapter = TTSChapterInfo(title: "Test Chapter", url: "test_url", index: 0, cachedContent: sampleContent)
        manager.startSpeaking(
            bookId: "test_book_id",
            chapters: [mockChapter],
            currentIndex: 0,
            chapterContent: sampleContent,
            startParagraphIndex: 0,
            bookTitle: "Test Book",
            extensionInfo: nil
        )
        
        XCTAssertGreaterThan(manager.paragraphs.count, 1)
        manager.stop()
    }
}
