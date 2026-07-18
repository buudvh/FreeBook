import Foundation
import SwiftData

struct ChapterMetadataSnapshot: Sendable, Equatable {
    let title: String
    let url: String
    let index: Int
    let host: String?
}

struct BookMetadataSnapshot: Sendable, Equatable {
    let bookId: String
    let title: String
    let author: String
    let coverUrl: String
    let desc: String
    let detailUrl: String
    let sourceName: String
    let sourceUrl: String
    let extensionPackageId: String
    let host: String?
    let chapters: [ChapterMetadataSnapshot]
}

struct PersistedChapterSnapshot: Sendable, Equatable {
    let title: String
    let url: String
    let index: Int
    let host: String?
    let content: String
}

enum ChapterPersistenceError: LocalizedError {
    case unavailableStore
    case missingBook(bookId: String)
    case invalidContent

    var errorDescription: String? {
        switch self {
        case .unavailableStore:
            return "Cơ sở dữ liệu cục bộ chưa sẵn sàng"
        case .missingBook(let bookId):
            return "Không tìm thấy sách \(bookId) để lưu chương"
        case .invalidContent:
            return "Nội dung chương không hợp lệ"
        }
    }
}

enum ChapterPersistenceState: Sendable, Equatable {
    case pending
    case persisted
    case failed
}

actor ChapterPersistenceStore {
    private struct PendingWrite {
        let id: UUID
        let task: Task<ChapterPersistenceState, Never>
    }

    private let container: ModelContainer
    private var pendingWrites: [String: PendingWrite] = [:]

    init(container: ModelContainer) {
        self.container = container
    }

    func readChapter(
        bookId: String,
        chapterIndex: Int,
        url: String
    ) throws -> PersistedChapterSnapshot? {
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        guard let book = books.first(where: { $0.bookId == bookId }) else {
            return nil
        }

        guard let chapter = matchingChapter(
            in: book.chapters,
            chapterIndex: chapterIndex,
            url: url
        ) else {
            return nil
        }

        guard let rawContent = chapter.content else {
            return nil
        }
        let normalizedContent = ChapterTextNormalizer.normalize(rawContent).content
        guard !normalizedContent.isEmpty else {
            return nil
        }

        if chapter.content != normalizedContent || !chapter.isCached {
            chapter.content = normalizedContent
            chapter.isCached = true
            do {
                try context.save()
            } catch {
                // Nội dung hợp lệ vẫn là cache đọc được; chỉ việc sửa cờ cũ là retry ở lần ghi sau.
                AppLogger.shared.log(
                    "⚠️ [ChapterPersistenceStore] Không thể sửa cờ cache (bookId)#(chapterIndex): (error.localizedDescription)"
                )
            }
        }

        return PersistedChapterSnapshot(
            title: chapter.title,
            url: chapter.url,
            index: chapter.index,
            host: chapter.host,
            content: normalizedContent
        )
    }

    func ensureBook(_ snapshot: BookMetadataSnapshot) throws {
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        let book: Book

        if let existing = books.first(where: { $0.bookId == snapshot.bookId }) {
            book = existing
        } else {
            book = Book(
                bookId: snapshot.bookId,
                title: snapshot.title,
                author: snapshot.author,
                coverUrl: snapshot.coverUrl,
                desc: snapshot.desc,
                detailUrl: snapshot.detailUrl,
                sourceName: snapshot.sourceName,
                sourceUrl: snapshot.sourceUrl,
                extensionPackageId: snapshot.extensionPackageId,
                isOnShelf: false,
                isHistory: true,
                host: snapshot.host
            )
            context.insert(book)
        }

        book.title = snapshot.title
        book.author = snapshot.author
        book.coverUrl = snapshot.coverUrl
        book.desc = snapshot.desc
        book.detailUrl = snapshot.detailUrl
        book.sourceName = snapshot.sourceName
        book.sourceUrl = snapshot.sourceUrl
        book.extensionPackageId = snapshot.extensionPackageId
        book.host = snapshot.host
        book.isHistory = true

        for item in snapshot.chapters {
            if let existing = matchingMetadataChapter(
                in: book.chapters,
                chapterIndex: item.index,
                url: item.url
            ) {
                existing.title = item.title
                existing.url = item.url
                existing.index = item.index
                existing.host = item.host
            } else {
                let chapter = Chapter(
                    id: chapterID(bookId: snapshot.bookId, chapter: item),
                    title: item.title,
                    url: item.url,
                    index: item.index,
                    host: item.host
                )
                book.chapters.append(chapter)
                context.insert(chapter)
            }
        }
        try context.save()
    }

    func enqueueWrite(
        key: String,
        bookId: String,
        book: BookMetadataSnapshot?,
        chapter: ChapterMetadataSnapshot,
        content: String
    ) {
        pendingWrites[key]?.task.cancel()
        let writeID = UUID()
        let task = Task { [weak self] in
            guard let self else { return ChapterPersistenceState.failed }
            return await self.persistWithRetry(
                key: key,
                bookId: bookId,
                book: book,
                chapter: chapter,
                content: content
            )
        }
        pendingWrites[key] = PendingWrite(id: writeID, task: task)
    }

    func flush(bookId: String) async {
        let matching = pendingWrites.filter { $0.key.hasPrefix("\(bookId)|") }
        for (key, pending) in matching {
            await pending.task.value
            if pendingWrites[key]?.id == pending.id {
                pendingWrites.removeValue(forKey: key)
            }
        }
    }

    func flushAll() async {
        let writes = pendingWrites
        for (key, pending) in writes {
            await pending.task.value
            if pendingWrites[key]?.id == pending.id {
                pendingWrites.removeValue(forKey: key)
            }
        }
    }

    private func persistWithRetry(
        key: String,
        bookId: String,
        book: BookMetadataSnapshot?,
        chapter: ChapterMetadataSnapshot,
        content: String
    ) async -> ChapterPersistenceState {
        for attempt in 0..<3 {
            guard !Task.isCancelled else { return .failed }
            do {
                try upsert(
                    bookId: bookId,
                    book: book,
                    chapter: chapter,
                    content: content
                )
                return .persisted
            } catch {
                guard attempt < 2 else {
                    AppLogger.shared.log(
                        "❌ [ChapterPersistenceStore] Không thể lưu \(key): \(error.localizedDescription)"
                    )
                    return .failed
                }
                try? await Task.sleep(nanoseconds: UInt64(attempt + 1) * 250_000_000)
            }
        }
        return .failed
    }

    private func upsert(
        bookId: String,
        book snapshot: BookMetadataSnapshot?,
        chapter metadata: ChapterMetadataSnapshot,
        content rawContent: String
    ) throws {
        let content = ChapterTextNormalizer.normalize(rawContent).content
        guard !content.isEmpty else {
            throw ChapterPersistenceError.invalidContent
        }

        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        let book: Book

        if let existing = books.first(where: { $0.bookId == bookId }) {
            book = existing
        } else if let snapshot {
            book = Book(
                bookId: snapshot.bookId,
                title: snapshot.title,
                author: snapshot.author,
                coverUrl: snapshot.coverUrl,
                desc: snapshot.desc,
                detailUrl: snapshot.detailUrl,
                sourceName: snapshot.sourceName,
                sourceUrl: snapshot.sourceUrl,
                extensionPackageId: snapshot.extensionPackageId,
                isOnShelf: false,
                isHistory: true,
                host: snapshot.host
            )
            context.insert(book)
        } else {
            throw ChapterPersistenceError.missingBook(bookId: bookId)
        }

        if let snapshot {
            book.title = snapshot.title
            book.author = snapshot.author
            book.coverUrl = snapshot.coverUrl
            book.desc = snapshot.desc
            book.detailUrl = snapshot.detailUrl
            book.sourceName = snapshot.sourceName
            book.sourceUrl = snapshot.sourceUrl
            book.extensionPackageId = snapshot.extensionPackageId
            book.host = snapshot.host
            for item in snapshot.chapters {
                let existing = matchingMetadataChapter(
                    in: book.chapters,
                    chapterIndex: item.index,
                    url: item.url
                )
                if let existing {
                    existing.title = item.title
                    existing.url = item.url
                    existing.index = item.index
                    existing.host = item.host
                } else {
                    let newChapter = Chapter(
                        id: chapterID(bookId: book.bookId, chapter: item),
                        title: item.title,
                        url: item.url,
                        index: item.index,
                        host: item.host
                    )
                    book.chapters.append(newChapter)
                    context.insert(newChapter)
                }
            }
        }

        book.isHistory = true

        guard let target = matchingMetadataChapter(
            in: book.chapters,
            chapterIndex: metadata.index,
            url: metadata.url
        ) else {
            let newChapter = Chapter(
                id: chapterID(bookId: book.bookId, chapter: metadata),
                title: metadata.title,
                url: metadata.url,
                index: metadata.index,
                content: content,
                isCached: true,
                host: metadata.host
            )
            book.chapters.append(newChapter)
            context.insert(newChapter)
            try context.save()
            return
        }

        target.title = metadata.title
        target.url = metadata.url
        target.index = metadata.index
        target.host = metadata.host
        target.content = content
        target.isCached = true
        book.isHistory = true
        try context.save()
    }

    private func matchingChapter(
        in chapters: [Chapter],
        chapterIndex: Int,
        url: String
    ) -> Chapter? {
        if !url.isEmpty {
            return chapters.first(where: { $0.url == url })
        }
        return chapters.first(where: { $0.index == chapterIndex })
    }

    private func matchingMetadataChapter(
        in chapters: [Chapter],
        chapterIndex: Int,
        url: String
    ) -> Chapter? {
        if !url.isEmpty, let exactURL = chapters.first(where: { $0.url == url }) {
            return exactURL
        }
        return chapters.first(where: { $0.index == chapterIndex })
    }

    private func chapterID(
        bookId: String,
        chapter: ChapterMetadataSnapshot
    ) -> String {
        let suffix = chapter.url.isEmpty ? "index-\(chapter.index)" : chapter.url
        return "\(bookId)_\(suffix)"
    }
}
