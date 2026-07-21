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

    func testBackgroundProcessorOffMainActor() async {
        let processor = TTSBackgroundProcessor.shared
        let dto = await processor.processChapter(
            bookId: "test-bg",
            chapterIndex: 0,
            chapterTitle: "Tiêu đề",
            rawContent: "Nội dung đoạn 1.\nNội dung đoạn 2.",
            chunkLength: 1000,
            isTranslationEnabled: false,
            sessionID: UUID(),
            generation: 1
        )

        XCTAssertEqual(dto.paragraphs.count, 3) // Tiêu đề + 2 đoạn
        XCTAssertEqual(dto.paragraphs[0].text, "Tiêu đề")
        XCTAssertEqual(dto.paragraphs[1].text, "Nội dung đoạn 1.")
    }

    func testStaleSessionOrGenerationResultCannotApply() async {
        let manager = TTSManager.shared
        let chapter = TTSChapterInfo(title: "Chapter 1", url: "url-1", index: 0)

        manager.startSpeaking(
            bookId: "test-stale",
            chapters: [chapter],
            currentIndex: 0,
            chapterContent: "Content 1",
            startParagraphIndex: 0,
            bookTitle: "Book title",
            extensionInfo: nil
        )

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)
        XCTAssertEqual(manager.playingBookId, "test-stale")
        XCTAssertEqual(manager.chapterTitle, "Chapter 1")

        manager.beginManualChapterNavigation(targetIndex: 1)
        manager.commitManualChapterNavigation(targetIndex: 0, chapterContent: "Content 0 Stale")
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertNotEqual(manager.chapterContent, "Content 0 Stale")
        manager.stop()
    }

    func testFiveBeginsAndOneCommitCausesSingleSwitch() async {
        let manager = TTSManager.shared
        let chaps = (0..<10).map { TTSChapterInfo(title: "Chapter \($0)", url: "url-\($0)", index: $0) }

        manager.startSpeaking(
            bookId: "test-coalesce",
            chapters: chaps,
            currentIndex: 0,
            chapterContent: "Chapter 0 content",
            startParagraphIndex: 0,
            bookTitle: "Book Title",
            extensionInfo: nil
        )
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        for i in 1...5 {
            manager.beginManualChapterNavigation(targetIndex: i)
        }

        manager.commitManualChapterNavigation(targetIndex: 5, chapterContent: "Chapter 5 final content")
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertEqual(manager.playingChapterIndex, 5)
        XCTAssertEqual(manager.chapterContent, "Chapter 5 final content")
        manager.stop()
    }

    func testAdjacentManualSwitchDoesNotDeactivateAudioSession() async {
        let manager = TTSManager.shared
        let chaps = [
            TTSChapterInfo(title: "C1", url: "url-1", index: 0),
            TTSChapterInfo(title: "C2", url: "url-2", index: 1)
        ]

        var deactivationCalled = false
        manager.onSetActive = { active in
            if !active {
                deactivationCalled = true
            }
        }
        defer { manager.onSetActive = nil }

        manager.startSpeaking(
            bookId: "test-audio",
            chapters: chaps,
            currentIndex: 0,
            chapterContent: "Chapter 1 Content",
            startParagraphIndex: 0,
            bookTitle: "Book title",
            extensionInfo: nil
        )
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        manager.beginManualChapterNavigation(targetIndex: 1)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertFalse(deactivationCalled, "Audio session should not be deactivated during manual navigation begin")

        manager.commitManualChapterNavigation(targetIndex: 1, chapterContent: "Chapter 2 Content")
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertEqual(manager.playingChapterIndex, 1)
        XCTAssertFalse(deactivationCalled, "Audio session should not be deactivated during manual navigation commit")

        manager.stop()
    }

    func testBackgroundProcessorTitleDisabled() async {
        let processor = TTSBackgroundProcessor.shared
        let dto = await processor.processChapter(
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
        let processor = TTSBackgroundProcessor.shared
        let dto = await processor.processChapter(
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

        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertFalse(manager.isPlaying)
        XCTAssertEqual(manager.paragraphs.count, 3)
        XCTAssertEqual(manager.paragraphs[0].text, "Chapter 1")
    }

    func testHasActivePlaybackOwnership() async {
        let manager = TTSManager.shared
        let mockChapter = TTSChapterInfo(title: "C1", url: "url-1", index: 0)

        manager.stop()
        XCTAssertFalse(manager.hasActivePlaybackOwnership(for: "test-ownership"))

        manager.startSpeaking(
            bookId: "test-ownership",
            chapters: [mockChapter],
            currentIndex: 0,
            chapterContent: "Content",
            startParagraphIndex: 0,
            bookTitle: "Title",
            extensionInfo: nil
        )
        try? await Task.sleep(nanoseconds: 100 * 1_000_000)

        XCTAssertTrue(manager.isPlaying)
        XCTAssertTrue(manager.hasActivePlaybackOwnership(for: "test-ownership"))
        XCTAssertFalse(manager.hasActivePlaybackOwnership(for: "unrelated-book"))

        // Manual navigation begin
        manager.beginManualChapterNavigation(targetIndex: 1)
        XCTAssertFalse(manager.isPlaying)
        XCTAssertTrue(manager.hasActivePlaybackOwnership(for: "test-ownership"), "Ownership must be preserved during manual navigation transition")

        // Try calling resume() during manual navigation handoff
        manager.resume()
        XCTAssertFalse(manager.isPlaying, "resume() must not set isPlaying to true during manual navigation")

        manager.abortManualChapterNavigation()
        XCTAssertFalse(manager.hasActivePlaybackOwnership(for: "test-ownership"))

        manager.stop()
    }

    private func nowPlayingPlaybackRate() -> Double? {
        let value = MPNowPlayingInfoCenter.default()
            .nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? NSNumber
        return value?.doubleValue
    }
}
