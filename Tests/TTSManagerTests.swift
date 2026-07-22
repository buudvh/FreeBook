import XCTest
import MediaPlayer
@testable import FreeBook

@MainActor
final class TTSManagerTests: XCTestCase {

    func testTextSegmentationUnderDefaultLength() async {
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

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertEqual(manager.paragraphs.count, 2)
        XCTAssertEqual(manager.paragraphs.first?.text, "Đoạn văn thứ nhất ngắn.")

        manager.stop()
    }

    func testTextSegmentationOverDefaultLength() async {
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

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertGreaterThan(manager.paragraphs.count, 1)
        manager.stop()
    }

    func testExplicitStartOnDifferentBookReplacesTTSSession() async {
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
        try? await Task.sleep(nanoseconds: 50 * 1_000_000)
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
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertEqual(manager.playingBookId, "book-b")
        XCTAssertEqual(manager.playingChapterUrl, "b-1")
        manager.stop()
    }

    func testRemoteCommandsAndNowPlayingStateStayInSync() async {
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
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
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
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(nowPlayingPlaybackRate(), 0)

        manager.resume()

        XCTAssertTrue(manager.isPlaying)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertTrue(commandCenter.pauseCommand.isEnabled)
        XCTAssertTrue(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertEqual(nowPlayingPlaybackRate(), manager.speed)

        manager.stop()

        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(commandCenter.playCommand.isEnabled)
        XCTAssertFalse(commandCenter.pauseCommand.isEnabled)
        XCTAssertFalse(commandCenter.togglePlayPauseCommand.isEnabled)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .stopped)
    }

    func testRemoteCommandIdempotencyAndImmediateStateSync() async {
        let manager = TTSManager.shared
        let chapter = TTSChapterInfo(title: "Idempotency", url: "idempotency-1", index: 0)
        defer { manager.stop() }

        manager.startSpeaking(
            bookId: "idempotent-book",
            chapters: [chapter],
            currentIndex: 0,
            chapterContent: "Testing idempotency without time debounce.",
            startParagraphIndex: 0,
            bookTitle: "Idempotent Book",
            extensionInfo: nil
        )
        try? await Task.sleep(nanoseconds: 50 * 1_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)

        // Multiple rapid pauses should be idempotent and maintain paused state
        manager.pause()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(nowPlayingPlaybackRate(), 0)

        manager.pause()
        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .paused)
        XCTAssertEqual(nowPlayingPlaybackRate(), 0)

        // Immediate resume on first call succeeds
        manager.resume()
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertEqual(nowPlayingPlaybackRate(), manager.speed)

        manager.resume()
        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(MPNowPlayingInfoCenter.default().playbackState, .playing)
        XCTAssertEqual(nowPlayingPlaybackRate(), manager.speed)
    }

    func testBackgroundProcessorOffMainActor() async {
        let processor = TTSBackgroundProcessor()
        let dto = try! await processor.processChapter(
            bookId: "test-bg",
            chapterIndex: 0,
            chapterTitle: "Tiêu đề",
            rawContent: "Nội dung đoạn 1.\nNội dung đoạn 2.",
            chunkLength: 1000,
            shouldTranslateRawContent: false,
            includeChapterTitle: true,
            sessionID: UUID(),
            generation: 1
        )

        XCTAssertEqual(dto.paragraphs.count, 3) // Tiêu đề + 2 đoạn
        XCTAssertEqual(dto.paragraphs[0].text, "Tiêu đề")
        XCTAssertEqual(dto.paragraphs[1].text, "Nội dung đoạn 1.")
    }

    func testBackgroundProcessorTitleDisabled() async {
        let processor = TTSBackgroundProcessor()
        let dto = try! await processor.processChapter(
            bookId: "test-bg",
            chapterIndex: 0,
            chapterTitle: "Tiêu đề chương",
            rawContent: "Dòng 1.\nDòng 2.",
            chunkLength: 1000,
            shouldTranslateRawContent: false,
            includeChapterTitle: false,
            sessionID: UUID(),
            generation: 1
        )
        XCTAssertEqual(dto.paragraphs.count, 2)
        XCTAssertEqual(dto.paragraphs[0].text, "Dòng 1.")
    }

    func testBackgroundProcessorTitleEnabled() async {
        let processor = TTSBackgroundProcessor()
        let dto = try! await processor.processChapter(
            bookId: "test-bg",
            chapterIndex: 0,
            chapterTitle: "Tiêu đề chương",
            rawContent: "Dòng 1.\nDòng 2.",
            chunkLength: 1000,
            shouldTranslateRawContent: false,
            includeChapterTitle: true,
            sessionID: UUID(),
            generation: 1
        )
        XCTAssertEqual(dto.paragraphs.count, 3)
        XCTAssertEqual(dto.paragraphs[0].text, "Tiêu đề chương")
        XCTAssertEqual(dto.paragraphs[1].text, "Dòng 1.")
    }

    func testPrepareSpeakingAsynchronouslyConstructsParagraphs() async {
        let manager = TTSManager.shared
        let mockChapter = TTSChapterInfo(title: "Chapter 1", url: "url-1", index: 0)
        let titlePreferenceKey = "showChapterTitle_test-prepare"
        UserDefaults.standard.set(true, forKey: titlePreferenceKey)
        defer { UserDefaults.standard.removeObject(forKey: titlePreferenceKey) }

        manager.stop()
        XCTAssertFalse(manager.isPlaying)
        manager.prepareSpeaking(
            bookId: "test-prepare",
            chapters: [mockChapter],
            currentIndex: 0,
            chapterContent: "Dòng 1.\nDòng 2.",
            startParagraphIndex: 0,
            bookTitle: "Book Title",
            extensionInfo: nil
        )

        await manager.waitForPreparationForTesting()

        XCTAssertFalse(manager.isPlaying)
        manager.startSpeaking(
            bookId: "test-prepare",
            chapters: [mockChapter],
            currentIndex: 0,
            chapterContent: "Dòng 1.\nDòng 2.",
            startParagraphIndex: 0,
            bookTitle: "Book Title",
            extensionInfo: nil
        )

        XCTAssertTrue(manager.isPlaying, "Prepared chapter should start without another processing wait")
        XCTAssertEqual(manager.paragraphs.count, 3)
        XCTAssertEqual(manager.paragraphs[0].text, "Chapter 1")
        manager.stop()
    }

    private func nowPlayingPlaybackRate() -> Double? {
        let value = MPNowPlayingInfoCenter.default()
            .nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber
        return value?.doubleValue
    }
}
