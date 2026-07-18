import XCTest
import MediaPlayer
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
        
        let mockChapter = TTSChapterInfo(title: "Test Chapter", url: "test_url", index: 0)
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
        
        let mockChapter = TTSChapterInfo(title: "Test Chapter", url: "test_url", index: 0)
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

    func testExplicitStartOnDifferentBookReplacesTTSSession() {
        let manager = TTSManager.shared
        let first = TTSChapterInfo(title: "A1", url: "a-1", index: 0)
        let second = TTSChapterInfo(title: "B1", url: "b-1", index: 0)

        manager.startSpeaking(
            bookId: "book-a",
            chapters: [first],
            currentIndex: 0,
            chapterContent: "Content A",
            startParagraphIndex: 0,
            bookTitle: "Book A",
            extensionInfo: nil
        )
        manager.pause()

        manager.startSpeaking(
            bookId: "book-b",
            chapters: [second],
            currentIndex: 0,
            chapterContent: "Content B",
            startParagraphIndex: 0,
            bookTitle: "Book B",
            extensionInfo: nil
        )

        XCTAssertEqual(manager.playingBookId, "book-b")
        XCTAssertEqual(manager.playingChapterUrl, "b-1")
        manager.stop()
    }

    func testRemoteCommandsAndNowPlayingStateStayInSync() {
        let manager = TTSManager.shared
        let commandCenter = MPRemoteCommandCenter.shared()
        let chapter = TTSChapterInfo(title: "Remote", url: "remote-1", index: 0)
        defer { manager.stop() }

        manager.startSpeaking(
            bookId: "remote-book",
            chapters: [chapter],
            currentIndex: 0,
            chapterContent: "Remote command test content.",
            startParagraphIndex: 0,
            bookTitle: "Remote Book",
            extensionInfo: nil
        )

        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)

        // Seed the already-visible Lock Screen card. State-only updates are
        // insufficient because its center button also follows playbackRate.
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "Remote Book",
            MPNowPlayingInfoPropertyPlaybackRate: manager.speed
        ]

        manager.pause()

        XCTAssertFalse(manager.isPlaying)
        XCTAssertTrue(commandCenter.playCommand.isEnabled)
        XCTAssertFalse(commandCenter.pauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(nowPlayingPlaybackRate(), 0)

        manager.resume()

        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertEqual(nowPlayingPlaybackRate(), manager.speed)
    }

    private func nowPlayingPlaybackRate() -> Double? {
        let value = MPNowPlayingInfoCenter.default()
            .nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber
        return value?.doubleValue
    }
}
