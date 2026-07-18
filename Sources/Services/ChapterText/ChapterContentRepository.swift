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
    let cachedContent: String?
    let extensionInfo: TTSExtensionInfo?
    let forceRefresh: Bool
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

    private struct CacheKey: Hashable {
        let bookId: String
        let chapterIndex: Int
        let url: String
    }

    private var container: ModelContainer?
    private var memory: [CacheKey: ChapterDocument] = [:]

    func configure(container: ModelContainer) {
        self.container = container
    }

    func store(_ document: ChapterDocument, bookId: String) {
        memory[CacheKey(bookId: bookId, chapterIndex: document.chapterIndex, url: document.url)] = document
    }

    func remove(bookId: String, chapterIndex: Int) {
        memory = memory.filter { key, _ in
            key.bookId != bookId || key.chapterIndex != chapterIndex
        }
    }

    func load(_ request: ChapterContentRequest) async throws -> ChapterContentResult {
        let key = CacheKey(
            bookId: request.bookId,
            chapterIndex: request.chapterIndex,
            url: request.url
        )

        if !request.forceRefresh, let document = memory[key] {
            return ChapterContentResult(document: document, origin: .memory)
        }

        if !request.forceRefresh,
           let content = request.cachedContent,
           !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let document = makeDocument(request: request, rawContent: content)
            memory[key] = document
            return ChapterContentResult(document: document, origin: .persistentCache)
        }

        if !request.forceRefresh, let content = try fetchPersistedContent(for: request) {
            let document = makeDocument(request: request, rawContent: content)
            memory[key] = document
            return ChapterContentResult(document: document, origin: .persistentCache)
        }

        guard let extensionInfo = request.extensionInfo else {
            throw ChapterContentRepositoryError.unavailableExtension
        }
        let rawContent = try await fetchFromExtension(request: request, extensionInfo: extensionInfo)
        let document = makeDocument(request: request, rawContent: rawContent.cleanHTML())
        guard !document.text.content.isEmpty else {
            throw ChapterContentRepositoryError.emptyContent
        }
        try persist(document, bookId: request.bookId)
        memory[key] = document
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

    private func fetchPersistedContent(for request: ChapterContentRequest) throws -> String? {
        guard let container else { return nil }
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        guard let book = books.first(where: { $0.bookId == request.bookId }),
              let chapter = book.chapters.first(where: {
                  $0.index == request.chapterIndex || $0.url == request.url
              }),
              chapter.isCached,
              let content = chapter.content,
              !content.isEmpty else { return nil }
        return content
    }

    private func persist(_ document: ChapterDocument, bookId: String) throws {
        guard let container else { return }
        let context = ModelContext(container)
        let books = try context.fetch(FetchDescriptor<Book>())
        guard let book = books.first(where: { $0.bookId == bookId }),
              let chapter = book.chapters.first(where: {
                  $0.index == document.chapterIndex || $0.url == document.url
              }) else { return }
        chapter.content = document.text.content
        chapter.isCached = true
        try context.save()
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
