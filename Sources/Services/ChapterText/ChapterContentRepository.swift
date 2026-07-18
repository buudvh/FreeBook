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

    private struct InFlightLoad {
        let id: UUID
        let task: Task<ChapterContentResult, Error>
    }

    private var persistenceStore: ChapterPersistenceStore?
    private var configuredContainerID: ObjectIdentifier?
    private var memory: [ChapterKey: ChapterDocument] = [:]
    private var inFlightLoads: [ChapterKey: InFlightLoad] = [:]

    func configure(container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        guard configuredContainerID != containerID else { return }
        for load in inFlightLoads.values {
            load.task.cancel()
        }
        inFlightLoads.removeAll()
        memory.removeAll()
        persistenceStore = ChapterPersistenceStore(container: container)
        configuredContainerID = containerID
    }

    func store(_ document: ChapterDocument, bookId: String) {
        memory[ChapterKey(bookId: bookId, chapterIndex: document.chapterIndex, url: document.url)] = document
    }

    func remove(bookId: String, chapterIndex: Int) {
        memory = memory.filter { key, _ in
            key.bookId != bookId || key.chapterIndex != chapterIndex
        }
    }

    func flush(bookId: String) async {
        await persistenceStore?.flush(bookId: bookId)
    }

    func flushAll() async {
        await persistenceStore?.flushAll()
    }

    func load(_ request: ChapterContentRequest) async throws -> ChapterContentResult {
        let key = ChapterKey(
            bookId: request.bookId,
            chapterIndex: request.chapterIndex,
            url: request.url
        )

        if !request.forceRefresh, let document = memory[key] {
            return ChapterContentResult(document: document, origin: .memory)
        }

        if !request.forceRefresh, let inFlight = inFlightLoads[key] {
            return try await inFlight.task.value
        }
        if request.forceRefresh, let inFlight = inFlightLoads[key] {
            inFlight.task.cancel()
        }

        let task = Task { [weak self] () throws -> ChapterContentResult in
            guard let self else {
                throw ChapterContentRepositoryError.emptyContent
            }
            return try await self.loadUnshared(request, key: key)
        }
        let loadID = UUID()
        inFlightLoads[key] = InFlightLoad(id: loadID, task: task)

        do {
            let result = try await task.value
            if inFlightLoads[key]?.id == loadID {
                inFlightLoads.removeValue(forKey: key)
            }
            return result
        } catch {
            if inFlightLoads[key]?.id == loadID {
                inFlightLoads.removeValue(forKey: key)
            }
            throw error
        }
    }

    private func loadUnshared(
        _ request: ChapterContentRequest,
        key: ChapterKey
    ) async throws -> ChapterContentResult {
        if !request.forceRefresh, let document = memory[key] {
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
                    memory[key] = document
                    return ChapterContentResult(document: document, origin: .persistentCache)
                }
            } catch {
                AppLogger.shared.log(
                    "❌ [ChapterContentRepository] Không thể đọc cache local \(request.bookId)#\(request.chapterIndex): \(error.localizedDescription)"
                )
            }
        }

        if let metadata = request.bookMetadata, let store = persistenceStore {
            do {
                try await store.ensureBook(metadata)
            } catch {
                AppLogger.shared.log(
                    "❌ [ChapterContentRepository] Không thể chuẩn bị metadata local \(request.bookId): \(error.localizedDescription)"
                )
            }
        }

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

        memory[key] = document
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
                try await ExtensionManager.shared.chap(
                    localPath: extensionInfo.localPath,
                    downloadUrl: extensionInfo.downloadUrl,
                    url: request.url,
                    host: request.host,
                    configJson: extensionInfo.configJson ?? "{}"
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
