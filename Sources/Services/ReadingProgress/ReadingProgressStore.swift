import Foundation
import SwiftData

enum ReadingProgressOwner: String, Sendable, Equatable {
    case reader
    case tts
}

struct ReadingProgressSnapshot: Sendable, Equatable {
    let bookId: String
    let chapterIndex: Int
    let paragraphIndex: Int
    let chapterTitle: String?
    let owner: ReadingProgressOwner
    let recordedAt: Date
}

actor ReadingProgressStore {
    static let shared = ReadingProgressStore()

    private let chapterRepository: any ChapterRepositoryProtocol

    init(chapterRepository: any ChapterRepositoryProtocol = ChapterSQLiteRepository()) {
        self.chapterRepository = chapterRepository
    }

    private var container: ModelContainer?
    private var latestByBook: [String: ReadingProgressSnapshot] = [:]
    private var ownerByBook: [String: ReadingProgressOwner] = [:]

    func configure(container: ModelContainer) {
        self.container = container
    }

    func claim(bookId: String, owner: ReadingProgressOwner) {
        guard !bookId.isEmpty else { return }
        if ownerByBook[bookId] == .tts, owner == .reader { return }
        ownerByBook[bookId] = owner
    }

    func record(_ snapshot: ReadingProgressSnapshot) {
        guard !snapshot.bookId.isEmpty else { return }
        if ownerByBook[snapshot.bookId] == .tts, snapshot.owner == .reader {
            return
        }
        if let current = latestByBook[snapshot.bookId], current.recordedAt > snapshot.recordedAt {
            return
        }
        latestByBook[snapshot.bookId] = snapshot
        ownerByBook[snapshot.bookId] = snapshot.owner
    }

    func checkpointAndRelease(
        _ snapshot: ReadingProgressSnapshot,
        owner: ReadingProgressOwner
    ) throws {
        record(snapshot)
        try persist(snapshot)
        if ownerByBook[snapshot.bookId] == owner {
            ownerByBook.removeValue(forKey: snapshot.bookId)
        }
    }

    func checkpoint(_ snapshot: ReadingProgressSnapshot) throws {
        record(snapshot)
        try persist(snapshot)
    }

    func flush(bookId: String) throws {
        guard let snapshot = latestByBook[bookId] else { return }
        try persist(snapshot)
    }

    func flushAll() throws {
        for snapshot in latestByBook.values {
            try persist(snapshot)
        }
    }

    private func persist(_ snapshot: ReadingProgressSnapshot) throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let books = try context.fetch(FetchDescriptor<Book>())
        guard let book = books.first(where: { $0.bookId == snapshot.bookId }) else { return }

        book.currentChapterIndex = snapshot.chapterIndex
        book.currentChapterPage = snapshot.paragraphIndex
        var resolvedTitle: String? = nil
        if let title = snapshot.chapterTitle, !title.isEmpty {
            resolvedTitle = title
        } else {
            let sema = DispatchSemaphore(value: 0)
            let bookId = snapshot.bookId
            let chapterIndex = snapshot.chapterIndex
            Task {
                resolvedTitle = (try? await self.chapterRepository.getChapter(bookId: bookId, index: chapterIndex))?.title
                sema.signal()
            }
            _ = sema.wait(timeout: .now() + 1.0)
        }
        book.currentChapterTitle = resolvedTitle ?? book.currentChapterTitle
        book.isHistory = true
        book.lastReadDate = snapshot.recordedAt
        try context.save()
    }
}
