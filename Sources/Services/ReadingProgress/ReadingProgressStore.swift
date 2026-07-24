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
    ) async throws {
        record(snapshot)
        try await persist(snapshot)
        if ownerByBook[snapshot.bookId] == owner {
            ownerByBook.removeValue(forKey: snapshot.bookId)
        }
    }

    func checkpoint(_ snapshot: ReadingProgressSnapshot) async throws {
        record(snapshot)
        try await persist(snapshot)
    }

    func flush(bookId: String) async throws {
        guard let snapshot = latestByBook[bookId] else { return }
        try await persist(snapshot)
    }

    func flushAll() async throws {
        for snapshot in latestByBook.values {
            try await persist(snapshot)
        }
    }

    private func persist(_ snapshot: ReadingProgressSnapshot) async throws {
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
        } else if let chap = try? await self.chapterRepository.getChapter(bookId: snapshot.bookId, index: snapshot.chapterIndex) {
            resolvedTitle = (chap.titleTrans?.isEmpty == false) ? chap.titleTrans : chap.title
        }
        book.currentChapterTitle = resolvedTitle ?? book.currentChapterTitle
        book.isHistory = true
        book.lastReadDate = snapshot.recordedAt
        try context.save()
        AppLogger.shared.log("💾 [ReadingProgressStore] Đã lưu bookmark cho sách \(snapshot.bookId): chapterIndex=\(snapshot.chapterIndex), title='\(book.currentChapterTitle)'")
    }
}
