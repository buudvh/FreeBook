import Foundation
import SwiftData

enum ChapterContentOrigin: Sendable, Equatable {
    case memory
    case persistentCache
    case extensionFetch
}

struct ChapterContentRequest: Sendable, Equatable {
    let bookId: String
    let chapterIndex: Int
    let title: String
    let url: String
    let host: String?
    let bookMetadata: BookMetadataSnapshot?
    let extensionInfo: TTSExtensionInfo?
    let forceRefresh: Bool
}

struct ChapterKey: Hashable, Sendable, Equatable {
    let bookId: String
    let chapterIndex: Int
    let url: String
}

struct ChapterContentResult: Sendable, Equatable {
    let document: ChapterDocument
    let origin: ChapterContentOrigin
}

enum ChapterContentRepositoryError: LocalizedError {
    case unavailableExtension
    case timedOut
    case emptyContent

    var errorDescription: String? {
        switch self {
        case .unavailableExtension:
            return "Không tìm thấy tiện ích bóc tách"
        case .timedOut:
            return "Tải chương quá thời gian cho phép"
        case .emptyContent:
            return "Chương không có nội dung"
        }
    }
}

actor ChapterContentRepository {
    static let shared = ChapterContentRepository()

    private struct MemoryEntry {
        let document: ChapterDocument
        let estimatedCost: Int
        var lastAccess: UInt64
    }

    private struct InFlightWaiter {
        let continuation: CheckedContinuation<ChapterContentResult, Error>
    }

    private struct InFlightLoad {
        let id: UUID
        let task: Task<Void, Never>
        var waiters: [UUID: InFlightWaiter]
    }

    private let maxMemoryEntryCount: Int
    private let maxMemoryCost: Int
    private var persistenceStore: ChapterPersistenceStore?
    private var configuredContainerID: ObjectIdentifier?
    private var memory: [ChapterKey: MemoryEntry] = [:]
    private var totalMemoryCost = 0
    private var memoryAccessSequence: UInt64 = 0
    private var inFlightLoads: [ChapterKey: InFlightLoad] = [:]

    init(
        maxMemoryEntryCount: Int = 12,
        maxMemoryCost: Int = 12 * 1_024 * 1_024
    ) {
        self.maxMemoryEntryCount = max(0, maxMemoryEntryCount)
        self.maxMemoryCost = max(0, maxMemoryCost)
    }

    func configure(container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        guard configuredContainerID != containerID else { return }
        cancelAllInFlightLoads()
        trimMemoryCache()
        persistenceStore = ChapterPersistenceStore(container: container)
        configuredContainerID = containerID
    }

    func store(_ document: ChapterDocument, bookId: String) {
        storeInMemory(
            document,
            for: ChapterKey(bookId: bookId, chapterIndex: document.chapterIndex, url: document.url)
        )
    }

    func remove(bookId: String, chapterIndex: Int) {
        let keys = memory.keys.filter {
            $0.bookId == bookId && $0.chapterIndex == chapterIndex
        }
        for key in keys {
            removeMemoryEntry(for: key)
        }
    }

    /// Releases only the repository's reusable RAM snapshots. Active Reader/TTS
    /// consumers retain their own document values, and persistent content remains
    /// available through the local-first store.
    func trimMemoryCache() {
        memory.removeAll(keepingCapacity: false)
        totalMemoryCost = 0
    }

    @discardableResult
    func flush(bookId: String) async -> [String: ChapterPersistenceState] {
        await persistenceStore?.flush(bookId: bookId) ?? [:]
    }

    @discardableResult
    func flushAll() async -> [String: ChapterPersistenceState] {
        await persistenceStore?.flushAll() ?? [:]
    }

    func saveCachedChapter(
        bookId: String,
        chapterIndex: Int,
        chapterTitle: String,
        chapterUrl: String,
        content: String,
        container: ModelContainer
    ) async throws {
        configure(container: container)
        guard let persistenceStore else {
            throw ChapterPersistenceError.unavailableStore
        }
        let metadata = ChapterMetadataSnapshot(
            title: chapterTitle,
            url: chapterUrl,
            index: chapterIndex
        )
        let key = Chapter.generateId(bookId: bookId, url: chapterUrl, index: chapterIndex)
        let noBookSnapshot: BookMetadataSnapshot? = nil
        await persistenceStore.enqueueWrite(
            key: key,
            bookId: bookId,
            book: noBookSnapshot,
            chapter: metadata,
            content: content
        )
        let results = await persistenceStore.flush(bookId: bookId)
        guard let state = results[key], state == .persisted else {
            throw ChapterPersistenceError.writeFailed(key: key)
        }
    }

    func saveChapterList(
        bookId: String,
        createSnapshot: TOCBookCreateSnapshot?,
        chapters: [ChapterMetadataSnapshot],
        mode: TOCReconciliationMode,
        protectedTTSChapter: ProtectedTTSChapter? = nil
    ) async throws -> SaveTOCResult {
        guard let persistenceStore else {
            throw ChapterPersistenceError.unavailableStore
        }
        return try await persistenceStore.saveChapterList(
            bookId: bookId,
            createSnapshot: createSnapshot,
            chapters: chapters,
            mode: mode,
            protectedTTSChapter: protectedTTSChapter
        )
    }

    func load(_ request: ChapterContentRequest) async throws -> ChapterContentResult {
        let key = ChapterKey(
            bookId: request.bookId,
            chapterIndex: request.chapterIndex,
            url: request.url
        )

        if !request.forceRefresh, let document = memoryDocument(for: key) {
            return ChapterContentResult(document: document, origin: .memory)
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                registerWaiter(
                    id: waiterID,
                    continuation: continuation,
                    request: request,
                    key: key
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(id: waiterID, key: key)
            }
        }
    }

    private func registerWaiter(
        id waiterID: UUID,
        continuation: CheckedContinuation<ChapterContentResult, Error>,
        request: ChapterContentRequest,
        key: ChapterKey
    ) {
        if !request.forceRefresh, let document = memoryDocument(for: key) {
            continuation.resume(returning: ChapterContentResult(document: document, origin: .memory))
            return
        }

        if !request.forceRefresh, var inFlight = inFlightLoads[key] {
            inFlight.waiters[waiterID] = InFlightWaiter(continuation: continuation)
            inFlightLoads[key] = inFlight
            return
        }

        if request.forceRefresh {
            cancelInFlightLoad(for: key)
        }

        let loadID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            let result: Result<ChapterContentResult, Error>
            do {
                try Task.checkCancellation()
                result = .success(try await self.loadUnshared(request, key: key))
            } catch {
                result = .failure(error)
            }
            await self.finishInFlightLoad(for: key, loadID: loadID, result: result)
        }

        inFlightLoads[key] = InFlightLoad(
            id: loadID,
            task: task,
            waiters: [waiterID: InFlightWaiter(continuation: continuation)]
        )
    }

    private func cancelWaiter(id waiterID: UUID, key: ChapterKey) {
        guard var inFlight = inFlightLoads[key],
              let waiter = inFlight.waiters.removeValue(forKey: waiterID) else { return }

        waiter.continuation.resume(throwing: CancellationError())
        if inFlight.waiters.isEmpty {
            inFlight.task.cancel()
            inFlightLoads.removeValue(forKey: key)
        } else {
            inFlightLoads[key] = inFlight
        }
    }

    private func finishInFlightLoad(
        for key: ChapterKey,
        loadID: UUID,
        result: Result<ChapterContentResult, Error>
    ) {
        guard let inFlight = inFlightLoads[key], inFlight.id == loadID else { return }
        inFlightLoads.removeValue(forKey: key)
        for waiter in inFlight.waiters.values {
            waiter.continuation.resume(with: result)
        }
    }

    private func cancelInFlightLoad(for key: ChapterKey) {
        guard let inFlight = inFlightLoads.removeValue(forKey: key) else { return }
        inFlight.task.cancel()
        for waiter in inFlight.waiters.values {
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    private func cancelAllInFlightLoads() {
        let loads = Array(inFlightLoads.values)
        inFlightLoads.removeAll()
        for inFlight in loads {
            inFlight.task.cancel()
            for waiter in inFlight.waiters.values {
                waiter.continuation.resume(throwing: CancellationError())
            }
        }
    }

    private func loadUnshared(
        _ request: ChapterContentRequest,
        key: ChapterKey
    ) async throws -> ChapterContentResult {
        if !request.forceRefresh, let document = memoryDocument(for: key) {
            return ChapterContentResult(document: document, origin: .memory)
        }

        if !request.forceRefresh, let store = persistenceStore {
            do {
                if let persisted = try await store.readChapter(
                    bookId: request.bookId,
                    chapterIndex: request.chapterIndex,
                    url: request.url
                ) {
                    try Task.checkCancellation()
                    let document = makeDocument(request: request, rawContent: persisted.content)
                    storeInMemory(document, for: key)
                    return ChapterContentResult(document: document, origin: .persistentCache)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogger.shared.log(
                    "❌ [ChapterContentRepository] Không thể đọc cache local \(request.bookId)#\(request.chapterIndex): \(error.localizedDescription)"
                )
            }
        }

        if let metadata = request.bookMetadata, let store = persistenceStore {
            do {
                try await store.ensureBook(metadata)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                AppLogger.shared.log(
                    "❌ [ChapterContentRepository] Không thể chuẩn bị metadata local \(request.bookId): \(error.localizedDescription)"
                )
            }
        }

        try Task.checkCancellation()
        guard let extensionInfo = request.extensionInfo else {
            throw ChapterContentRepositoryError.unavailableExtension
        }

        let rawContent = try await fetchFromExtension(request: request, extensionInfo: extensionInfo)
        try Task.checkCancellation()
        let document = makeDocument(request: request, rawContent: rawContent.cleanHTML())
        guard !document.text.content.isEmpty else {
            throw ChapterContentRepositoryError.emptyContent
        }

        try Task.checkCancellation()

        storeInMemory(document, for: key)
        let chapter = ChapterMetadataSnapshot(
            title: request.title,
            url: request.url,
            index: request.chapterIndex,
            host: request.host
        )
        await persistenceStore?.enqueueWrite(
            key: "\(request.bookId)|\(request.chapterIndex)|\(request.url)",
            bookId: request.bookId,
            book: request.bookMetadata,
            chapter: chapter,
            content: document.text.content
        )
        return ChapterContentResult(document: document, origin: .extensionFetch)
    }

    private func memoryDocument(for key: ChapterKey) -> ChapterDocument? {
        guard var entry = memory[key] else { return nil }
        memoryAccessSequence &+= 1
        entry.lastAccess = memoryAccessSequence
        memory[key] = entry
        return entry.document
    }

    private func storeInMemory(_ document: ChapterDocument, for key: ChapterKey) {
        removeMemoryEntry(for: key)

        let cost = estimatedMemoryCost(of: document)
        guard maxMemoryEntryCount > 0, maxMemoryCost > 0, cost <= maxMemoryCost else { return }

        memoryAccessSequence &+= 1
        memory[key] = MemoryEntry(
            document: document,
            estimatedCost: cost,
            lastAccess: memoryAccessSequence
        )
        totalMemoryCost += cost
        evictMemoryIfNeeded()
    }

    private func removeMemoryEntry(for key: ChapterKey) {
        guard let removed = memory.removeValue(forKey: key) else { return }
        totalMemoryCost = max(0, totalMemoryCost - removed.estimatedCost)
    }

    private func evictMemoryIfNeeded() {
        while memory.count > maxMemoryEntryCount || totalMemoryCost > maxMemoryCost {
            guard let leastRecentKey = memory.min(by: {
                $0.value.lastAccess < $1.value.lastAccess
            })?.key else { break }
            removeMemoryEntry(for: leastRecentKey)
        }
    }

    private func estimatedMemoryCost(of document: ChapterDocument) -> Int {
        var cost = document.title.utf8.count + document.url.utf8.count
        cost += document.host?.utf8.count ?? 0
        cost += document.text.content.utf8.count
        for line in document.text.lines {
            cost += line.text.utf8.count + 64
        }
        return max(1, cost)
    }

    private func makeDocument(
        request: ChapterContentRequest,
        rawContent: String
    ) -> ChapterDocument {
        ChapterDocument(
            chapterIndex: request.chapterIndex,
            title: request.title,
            url: request.url,
            host: request.host,
            text: ChapterTextNormalizer.normalize(rawContent)
        )
    }

    private func fetchFromExtension(
        request: ChapterContentRequest,
        extensionInfo: TTSExtensionInfo
    ) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await SourceRuntime.chapter(
                    packageId: extensionInfo.packageId, localPath: extensionInfo.localPath,
                    downloadUrl: extensionInfo.downloadUrl, url: request.url, host: request.host,
                    configJson: extensionInfo.configJson ?? "{}", bookId: request.bookId,
                    chapterIndex: request.chapterIndex, chapterTitle: request.title,
                    bookUrl: request.bookMetadata?.detailUrl
                )
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 30_000_000_000)
                throw ChapterContentRepositoryError.timedOut
            }
            guard let result = try await group.next() else {
                throw ChapterContentRepositoryError.emptyContent
            }
            group.cancelAll()
            return result
        }
    }
}
