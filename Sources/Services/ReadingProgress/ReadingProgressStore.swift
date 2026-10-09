import Foundation
import SwiftData

public enum ReadingProgressOwner: String, Sendable, Equatable {
    case reader
    case tts
}

public struct ReadingProgressSnapshot: Sendable, Equatable {
    public let bookId: String
    public let chapterIndex: Int
    public let paragraphIndex: Int
    public let chapterTitle: String?
    public let owner: ReadingProgressOwner
    public let recordedAt: Date

    public init(
        bookId: String,
        chapterIndex: Int,
        paragraphIndex: Int,
        chapterTitle: String? = nil,
        owner: ReadingProgressOwner = .reader,
        recordedAt: Date = Date()
    ) {
        self.bookId = bookId
        self.chapterIndex = chapterIndex
        self.paragraphIndex = paragraphIndex
        self.chapterTitle = chapterTitle
        self.owner = owner
        self.recordedAt = recordedAt
    }
}

public actor ReadingProgressStore {
    public static let shared = ReadingProgressStore()

    private var container: ModelContainer?
    private var latestByBook: [String: ReadingProgressSnapshot] = [:]
    private var ownerByBook: [String: ReadingProgressOwner] = [:]
    // Snapshot đã ghi DB thành công gần nhất cho mỗi sách; flush/flushAll bỏ qua khi không có gì mới.
    private var persistedByBook: [String: ReadingProgressSnapshot] = [:]

    public func scheduleSave(bookId: String, chapterIndex: Int, page: Int) {
        let snapshot = ReadingProgressSnapshot(bookId: bookId, chapterIndex: chapterIndex, paragraphIndex: page)
        record(snapshot)
    }

    public func configure(container: ModelContainer) {
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
        guard let snapshot = latestByBook[bookId], !isAlreadyPersisted(snapshot) else { return }
        try await persist(snapshot)
    }

    func flushAll() async throws {
        for snapshot in latestByBook.values where !isAlreadyPersisted(snapshot) {
            try await persist(snapshot)
        }
    }

    private func isAlreadyPersisted(_ snapshot: ReadingProgressSnapshot) -> Bool {
        persistedByBook[snapshot.bookId] == snapshot
    }

    private func persist(_ snapshot: ReadingProgressSnapshot) async throws {
        guard let container else { return }
        let context = ModelContext(container)
        context.autosaveEnabled = false
        let targetBookId = snapshot.bookId
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == targetBookId })
        descriptor.fetchLimit = 1
        guard let book = try context.fetch(descriptor).first else { return }

        let fallbackTitleFromStore: String?
        if !ChapterStoreConfiguration.enableSwiftDataTOCWrite {
            fallbackTitleFromStore = (try? await ChapterStore.shared.fetchRange(bookId: snapshot.bookId, startIndex: snapshot.chapterIndex, count: 1))?.first?.title
        } else {
            fallbackTitleFromStore = nil
        }

        let snapshotOriginalTitle = snapshot.chapterTitle.flatMap { title in
            title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : title
        }

        book.currentChapterIndex = snapshot.chapterIndex
        book.currentChapterPage = snapshot.paragraphIndex
        book.currentChapterTitle = snapshotOriginalTitle
            ?? fallbackTitleFromStore
            ?? book.chapters.first(where: { $0.index == snapshot.chapterIndex })?.title
            ?? book.currentChapterTitle
        book.isHistory = true
        book.lastReadDate = snapshot.recordedAt
        try context.save()
        persistedByBook[snapshot.bookId] = snapshot
    }
}
