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
        
        manager.startSpeaking(chapterContent: sampleContent, startCharIndex: 0, bookTitle: "Test Book", chapterTitle: "Test Chapter")
        
        XCTAssertEqual(manager.paragraphs.count, 1)
        XCTAssertEqual(manager.paragraphs.first?.text, "Đoạn văn thứ nhất ngắn.\nĐoạn văn thứ hai cũng ngắn.")
        
        manager.stop()
    }
    
    func testTextSegmentationOverDefaultLength() {
        let manager = TTSManager.shared
        manager.chunkLength = 20
        
        let sampleContent = "Đây là một câu rất dài vượt quá độ dài giới hạn hai mươi ký tự."
        
        manager.startSpeaking(chapterContent: sampleContent, startCharIndex: 0, bookTitle: "Test Book", chapterTitle: "Test Chapter")
        
        XCTAssertGreaterThan(manager.paragraphs.count, 1)
        manager.stop()
    }
}
