import Foundation
import SwiftData

struct ChapterMetadataSnapshot: Sendable, Equatable {
    let title: String
    let url: String
    let index: Int
    let host: String?
    let titleTrans: String?

    init(title: String, url: String, index: Int, host: String? = nil, titleTrans: String? = nil) {
        self.title = title
        self.url = url
        self.index = index
        self.host = host
        self.titleTrans = titleTrans
    }
}

struct ProtectedTTSChapter: Sendable, Equatable {
    let bookId: String
    let index: Int
    let url: String
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

struct TOCBookCreateSnapshot: Sendable, Equatable {
    let bookId: String
    let title: String
    let author: String
    let coverUrl: String
    let desc: String
    let detailUrl: String
    let sourceName: String
    let sourceUrl: String
    let extensionPackageId: String
    let currentChapterIndex: Int
    let currentChapterPage: Int
    let currentChapterTitle: String
    let isOnShelf: Bool
    let isHistory: Bool
    let host: String?
}

enum TOCReconciliationMode: Sendable, Equatable {
    case replaceFullTOC
    case upsertPage
}

struct SaveTOCResult: Sendable, Equatable {
    let inserted: Int
    let updated: Int
    let deleted: Int
    let totalChapters: Int
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
    ) async throws -> PersistedChapterSnapshot? {
        let context = ModelContext(container)
        guard let book = try fetchBook(bookId: bookId, in: context) else {
            return nil
        }

        guard let chapter = matchingChapter(
            in: book.chapters,
            chapterIndex: chapterIndex,
            url: url
        ) else {
            return nil
        }

        guard chapter.isCached, chapter.length > 0 else {
            return nil
        }

        do {
            let rawContent = try await BookBinManager.shared.readChapterContent(
                bookId: bookId,
                offset: chapter.offset,
                length: chapter.length
            )
            let normalizedContent = ChapterTextNormalizer.normalize(rawContent).content
            guard !normalizedContent.isEmpty else {
                return nil
            }

            return PersistedChapterSnapshot(
                title: chapter.title,
                url: chapter.url,
                index: chapter.index,
                host: chapter.host,
                content: normalizedContent
            )
        } catch {
            AppLogger.shared.log("❌ [ChapterPersistenceStore] Lỗi đọc nội dung chương: \(error.localizedDescription)")
            return nil
        }
    }

    func ensureBook(_ snapshot: BookMetadataSnapshot) throws {
        let context = ModelContext(container)
        let book: Book

        if let existing = try fetchBook(bookId: snapshot.bookId, in: context) {
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

        let pool = ReconciliationPool(chapters: book.chapters)
        var existingIDs = Set(book.chapters.map { $0.id })

        for item in snapshot.chapters {
            if let existing = pool.consume(url: item.url, index: item.index) {
                existing.title = item.title
                existing.url = item.url
                existing.index = item.index
                existing.host = item.host
            } else {
                let newId = allocateNewChapterId(bookId: snapshot.bookId, item: item, existingIDs: &existingIDs)
                let chapter = Chapter(
                    id: newId,
                    bookId: snapshot.bookId,
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

    func saveChapterList(
        bookId: String,
        createSnapshot: TOCBookCreateSnapshot?,
        chapters: [ChapterMetadataSnapshot],
        mode: TOCReconciliationMode,
        protectedTTSChapter: ProtectedTTSChapter? = nil
    ) throws -> SaveTOCResult {
        let t0 = CFAbsoluteTimeGetCurrent()
        var tFetchBook: CFAbsoluteTime = 0
        var tFetchChapters: CFAbsoluteTime = 0
        var tReconcile: CFAbsoluteTime = 0
        var tSave: CFAbsoluteTime = 0

        var isNewBook: Bool? = nil
        let bookHash = String(Chapter.hashUrl(bookId).prefix(8))
        var status = "failed"

        defer {
            let tTotal = (CFAbsoluteTimeGetCurrent() - t0) * 1000.0
            let fetchBookMs = tFetchBook * 1000.0
            let fetchChaptersMs = tFetchChapters * 1000.0
            let reconcileMs = tReconcile * 1000.0
            let saveMs = tSave * 1000.0
            let isNewBookStr = isNewBook.map { String($0) } ?? "unknown"

            AppLogger.shared.log(
                "[TOC Performance] bookHash: \(bookHash), mode: \(mode), items: \(chapters.count), isNewBook: \(isNewBookStr), status: \(status) | fetchBook: \(String(format: "%.1fms", fetchBookMs)), fetchChapters: \(String(format: "%.1fms", fetchChaptersMs)), reconcile: \(String(format: "%.1fms", reconcileMs)), save: \(String(format: "%.1fms", saveMs)) | total: \(String(format: "%.1fms", tTotal))"
            )
        }

        let context = ModelContext(container)
        let tBookStart = CFAbsoluteTimeGetCurrent()
        let fetchedBook: Book?
        do {
            fetchedBook = try fetchBook(bookId: bookId, in: context)
            tFetchBook = CFAbsoluteTimeGetCurrent() - tBookStart
        } catch {
            tFetchBook = CFAbsoluteTimeGetCurrent() - tBookStart
            if error is CancellationError || Task.isCancelled {
                status = "cancelled"
            }
            throw error
        }

        let book: Book
        let currentChapters: [Chapter]
        let tReconcileStart: CFAbsoluteTime

        if let existing = fetchedBook {
            isNewBook = false
            book = existing

            let tChapStart = CFAbsoluteTimeGetCurrent()
            currentChapters = book.chapters
            tFetchChapters = CFAbsoluteTimeGetCurrent() - tChapStart

            tReconcileStart = CFAbsoluteTimeGetCurrent()
            if let createSnapshot {
                applyMetadata(from: createSnapshot, to: book)
            }
        } else if let createSnapshot {
            isNewBook = true
            tReconcileStart = CFAbsoluteTimeGetCurrent()
            book = Book(
                bookId: createSnapshot.bookId,
                title: createSnapshot.title,
                author: createSnapshot.author,
                coverUrl: createSnapshot.coverUrl,
                desc: createSnapshot.desc,
                detailUrl: createSnapshot.detailUrl,
                sourceName: createSnapshot.sourceName,
                sourceUrl: createSnapshot.sourceUrl,
                extensionPackageId: createSnapshot.extensionPackageId,
                currentChapterIndex: createSnapshot.currentChapterIndex,
                currentChapterPage: createSnapshot.currentChapterPage,
                currentChapterTitle: createSnapshot.currentChapterTitle,
                isOnShelf: createSnapshot.isOnShelf,
                isHistory: createSnapshot.isHistory,
                host: createSnapshot.host
            )
            context.insert(book)
            currentChapters = []
            tFetchChapters = 0
        } else {
            tReconcileStart = CFAbsoluteTimeGetCurrent()
            tFetchChapters = 0
            tReconcile = CFAbsoluteTimeGetCurrent() - tReconcileStart
            throw ChapterPersistenceError.missingBook(bookId: bookId)
        }

        do {
            if (book.host == nil || book.host?.isEmpty == true),
               let firstHost = chapters.first?.host,
               !firstHost.isEmpty {
                book.host = firstHost
            }

            let pool = ReconciliationPool(chapters: currentChapters)
            var existingIDs = Set(currentChapters.map { $0.id })
            var inserted = 0
            var updated = 0

            for item in chapters {
                try Task.checkCancellation()
                if let existing = pool.consume(url: item.url, index: item.index) {
                    existing.title = item.title
                    existing.url = item.url
                    existing.index = item.index
                    existing.host = item.host
                    if let titleTrans = item.titleTrans, !titleTrans.isEmpty {
                        existing.titleTrans = titleTrans
                    }
                    updated += 1
                } else {
                    let newId = allocateNewChapterId(bookId: book.bookId, item: item, existingIDs: &existingIDs)
                    let chapter = Chapter(
                        id: newId,
                        bookId: book.bookId,
                        title: item.title,
                        url: item.url,
                        index: item.index,
                        host: item.host
                    )
                    if let titleTrans = item.titleTrans, !titleTrans.isEmpty {
                        chapter.titleTrans = titleTrans
                    }
                    book.chapters.append(chapter)
                    context.insert(chapter)
                    inserted += 1
                }
            }

            var deleted = 0
            if mode == .replaceFullTOC {
                for stale in pool.remaining() {
                    try Task.checkCancellation()
                    let isPlayingChapter = protectedTTSChapter != nil
                        && protectedTTSChapter?.bookId == book.bookId
                        && protectedTTSChapter?.index == stale.index
                        && (stale.url.isEmpty || protectedTTSChapter?.url == stale.url)
                    if !isPlayingChapter {
                        book.chapters.removeAll(where: { $0 === stale })
                        context.delete(stale)
                        deleted += 1
                    }
                }
            }

            try Task.checkCancellation()
            tReconcile = CFAbsoluteTimeGetCurrent() - tReconcileStart

            let tSaveStart = CFAbsoluteTimeGetCurrent()
            do {
                try context.save()
                tSave = CFAbsoluteTimeGetCurrent() - tSaveStart
            } catch {
                tSave = CFAbsoluteTimeGetCurrent() - tSaveStart
                throw error
            }

            status = "success"
            let totalChapters = book.chapters.count
            return SaveTOCResult(inserted: inserted, updated: updated, deleted: deleted, totalChapters: totalChapters)
        } catch {
            if tReconcile == 0 {
                tReconcile = CFAbsoluteTimeGetCurrent() - tReconcileStart
            }
            if error is CancellationError || Task.isCancelled {
                status = "cancelled"
            }
            throw error
        }
    }

    private func applyMetadata(from snapshot: TOCBookCreateSnapshot, to book: Book) {
        book.title = snapshot.title
        book.author = snapshot.author
        book.coverUrl = snapshot.coverUrl
        book.desc = snapshot.desc
        book.detailUrl = snapshot.detailUrl
        book.sourceName = snapshot.sourceName
        book.sourceUrl = snapshot.sourceUrl
        book.extensionPackageId = snapshot.extensionPackageId
        book.host = snapshot.host
    }

    private func allocateNewChapterId(
        bookId: String,
        item: ChapterMetadataSnapshot,
        existingIDs: inout Set<String>
    ) -> String {
        let normalId = Chapter.generateId(bookId: bookId, url: item.url, index: item.index)
        var candidateId = normalId
        if existingIDs.contains(candidateId) {
            let fallbackBase = "\(bookId.count):\(bookId)|I:\(item.index)"
            candidateId = fallbackBase
            var suffix = 1
            while existingIDs.contains(candidateId) {
                candidateId = "\(fallbackBase)_col_\(suffix)"
                suffix += 1
            }
        }
        existingIDs.insert(candidateId)
        return candidateId
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
            _ = await pending.task.value
            if pendingWrites[key]?.id == pending.id {
                pendingWrites.removeValue(forKey: key)
            }
        }
    }

    func flushAll() async {
        let writes = pendingWrites
        for (key, pending) in writes {
            _ = await pending.task.value
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
                try await upsert(
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
    ) async throws {
        let content = ChapterTextNormalizer.normalize(rawContent).content
        guard !content.isEmpty else {
            throw ChapterPersistenceError.invalidContent
        }

        // Ghi nội dung vào file nhị phân qua BookBinManager
        let (offset, length) = try await BookBinManager.shared.writeChapterContent(bookId: bookId, content: content)

        let context = ModelContext(container)
        let book: Book

        if let existing = try fetchBook(bookId: bookId, in: context) {
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

            let pool = ReconciliationPool(chapters: book.chapters)
            var existingIDs = Set(book.chapters.map { $0.id })

            for item in snapshot.chapters {
                if let existing = pool.consume(url: item.url, index: item.index) {
                    existing.title = item.title
                    existing.url = item.url
                    existing.index = item.index
                    existing.host = item.host
                } else {
                    let newId = allocateNewChapterId(bookId: book.bookId, item: item, existingIDs: &existingIDs)
                    let newChapter = Chapter(
                        id: newId,
                        bookId: book.bookId,
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

        guard let target = matchingMetadataChapter(in: book.chapters, chapterIndex: metadata.index, url: metadata.url) else {
            var existingIDs = Set(book.chapters.map { $0.id })
            let newId = allocateNewChapterId(bookId: book.bookId, item: metadata, existingIDs: &existingIDs)
            let newChapter = Chapter(
                id: newId,
                bookId: book.bookId,
                title: metadata.title,
                url: metadata.url,
                index: metadata.index,
                isCached: true,
                offset: offset,
                length: length,
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
        target.offset = offset
        target.length = length
        target.isCached = true
        book.isHistory = true
        try context.save()
    }

    private func fetchBook(bookId: String, in context: ModelContext) throws -> Book? {
        let targetBookId = bookId
        var descriptor = FetchDescriptor<Book>(
            predicate: #Predicate<Book> { $0.bookId == targetBookId }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
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
}

fileprivate class ReconciliationPool {
    private var urlMap: [String: [Chapter]] = [:]
    private var indexMap: [Int: [Chapter]] = [:]
    private var consumed: Set<PersistentIdentifier> = []

    init(chapters: [Chapter]) {
        for chap in chapters {
            if !chap.url.isEmpty {
                urlMap[chap.url, default: []].append(chap)
            }
            indexMap[chap.index, default: []].append(chap)
        }
    }

    func consume(url: String, index: Int) -> Chapter? {
        if !url.isEmpty, let list = urlMap[url] {
            for chap in list {
                if !consumed.contains(chap.persistentModelID) {
                    consumed.insert(chap.persistentModelID)
                    return chap
                }
            }
        }
        if let list = indexMap[index] {
            for chap in list {
                if !consumed.contains(chap.persistentModelID) {
                    consumed.insert(chap.persistentModelID)
                    return chap
                }
            }
        }
        return nil
    }

    func remaining() -> [Chapter] {
        var result: [Chapter] = []
        for list in urlMap.values {
            for chap in list where !consumed.contains(chap.persistentModelID) {
                result.append(chap)
            }
        }
        for list in indexMap.values {
            for chap in list where !consumed.contains(chap.persistentModelID) && !result.contains(where: { $0.persistentModelID == chap.persistentModelID }) {
                result.append(chap)
            }
        }
        return result
    }
}
