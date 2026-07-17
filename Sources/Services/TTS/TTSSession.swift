import Foundation
import Combine

public struct TTSSessionSnapshot: Equatable {
    public let bookId: String
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let isPlaying: Bool

    public static let empty = TTSSessionSnapshot(
        bookId: "",
        chapterIndex: -1,
        paragraphIndex: -1,
        isPlaying: false
    )
}

public struct PlaybackQueue {
    public private(set) var chapters: [TTSChapterInfo]
    public private(set) var currentIndex: Int

    public init(chapters: [TTSChapterInfo] = [], currentIndex: Int = -1) {
        self.chapters = chapters
        self.currentIndex = currentIndex
    }

    public var current: TTSChapterInfo? {
        guard currentIndex >= 0 && currentIndex < chapters.count else { return nil }
        return chapters[currentIndex]
    }

    public var next: TTSChapterInfo? {
        let index = currentIndex + 1
        guard index >= 0 && index < chapters.count else { return nil }
        return chapters[index]
    }

    public mutating func move(to index: Int) {
        guard index >= 0 && index < chapters.count else { return }
        currentIndex = index
    }
}

@MainActor
public final class TTSSession: ObservableObject {
    public static let shared = TTSSession()

    @Published public private(set) var snapshot: TTSSessionSnapshot = .empty
    @Published public private(set) var queue = PlaybackQueue()

    private init() {}

    public func start(bookId: String, chapters: [TTSChapterInfo], chapterIndex: Int, paragraphIndex: Int) {
        queue = PlaybackQueue(chapters: chapters, currentIndex: chapterIndex)
        snapshot = TTSSessionSnapshot(
            bookId: bookId,
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            isPlaying: true
        )
    }

    public func update(chapterIndex: Int, paragraphIndex: Int, isPlaying: Bool) {
        queue.move(to: chapterIndex)
        snapshot = TTSSessionSnapshot(
            bookId: snapshot.bookId,
            chapterIndex: chapterIndex,
            paragraphIndex: paragraphIndex,
            isPlaying: isPlaying
        )
    }

    public func stop() {
        snapshot = TTSSessionSnapshot(
            bookId: snapshot.bookId,
            chapterIndex: snapshot.chapterIndex,
            paragraphIndex: snapshot.paragraphIndex,
            isPlaying: false
        )
    }
}
