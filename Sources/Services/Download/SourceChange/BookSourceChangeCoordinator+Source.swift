import Foundation
import SwiftData

/// Phần tra cứu của lượt đổi nguồn: truyện đích có sẵn trên máy, chi tiết + mục lục ở nguồn mới.
extension BookSourceChangeCoordinator {
    /// Truyện đã có trên máy ở đúng nguồn mới — chỉ giá trị cần dùng, không mang instance `Book` qua ranh giới luồng.
    struct ExistingBook: Sendable {
        let bookId: String
        let lastReadDate: Date
        let isOnShelf: Bool
    }

    struct SourceSnapshot {
        let createSnapshot: TOCBookCreateSnapshot
        let chapters: [ChapterMetadataSnapshot]
    }

    /// Truyện cùng tiện ích + cùng link chi tiết (khớp như `BookDetailView.localBook`), khác truyện cũ. Có nhiều bản (đổi
    /// nguồn nhiều lần trước 1.3.689) thì lấy bản đọc gần nhất. Lọc trên RAM: không viết predicate chuỗi nhiều điều kiện.
    nonisolated static func findBook(
        packageId: String,
        detailUrl: String,
        excluding excludedBookId: String,
        container: ModelContainer
    ) async -> ExistingBook? {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            guard let books = try? context.fetch(FetchDescriptor<Book>()) else { return nil }
            return books
                .filter { $0.extensionPackageId == packageId && $0.detailUrl == detailUrl && $0.bookId != excludedBookId }
                .max(by: { $0.lastReadDate < $1.lastReadDate })
                .map { ExistingBook(bookId: $0.bookId, lastReadDate: $0.lastReadDate, isOnShelf: $0.isOnShelf) }
        }.value
    }

    nonisolated static func bookExists(bookId: String, container: ModelContainer) async -> Bool {
        await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.bookId == bookId })
            descriptor.fetchLimit = 1
            return ((try? context.fetchCount(descriptor)) ?? 0) > 0
        }.value
    }

    /// Chi tiết + toàn bộ mục lục ở nguồn mới. Cùng quy tắc với Chi tiết truyện (trang đầu = `pages.first`); mục lục
    /// rỗng/trang rỗng ⇒ ném lỗi **trước** khi ghi gì, truyện cũ và chương đã tải không bị đụng tới.
    func fetchSource(_ request: Request, newBookId: String) async throws -> SourceSnapshot {
        let ext = request.ext
        let result = request.result
        let path = ext.localPath
        // Ngữ cảnh theo `newBookId`: nguồn Legado ghi trạng thái theo đúng id của truyện đích.
        let context = SourceRuntimeContext(bookId: newBookId, bookUrl: result.link, bookName: result.name, bookAuthor: result.author, isInteractive: true)
        let detailResult = try await SourceRuntime.shared.detail(localPath: path, downloadUrl: ext.downloadUrl, url: result.link, host: ExtensionHostResolver.nonEmpty(result.host) ?? ext.sourceUrl, configJson: ext.configJson, context: context)
        // Host sách: host detail → host item tìm kiếm → source (detail thường không trả host).
        let bookHost = ExtensionHostResolver.nonEmpty(detailResult.host) ?? ExtensionHostResolver.nonEmpty(result.host) ?? ext.sourceUrl
        let snapshot = ExtensionExecutionSnapshot(packageId: ext.packageId, name: ext.name, localPath: path, downloadUrl: ext.downloadUrl, configJson: ext.configJson)
        let tocChapters = try await BookDetailLoader.shared.fetchFullTOC(snapshot: snapshot, url: result.link, host: bookHost, context: context).chapters

        let savedDesc = detailResult.detail.isEmpty ? detailResult.description.cleanHTML() : "\(detailResult.description.cleanHTML())\n\n---\n\(detailResult.detail.cleanHTML())"
        // Giữ nguyên chỉ số chương (người dùng chọn, 1.3.669): chương đã tải được chép theo vị trí.
        let initialChapterIndex = min(request.oldChapterIndex, max(0, tocChapters.count - 1))
        let initialChapterTitle = tocChapters.isEmpty ? "" : tocChapters[initialChapterIndex].name

        let createSnapshot = TOCBookCreateSnapshot(
            bookId: newBookId,
            title: detailResult.name,
            author: detailResult.author,
            coverUrl: detailResult.cover,
            desc: savedDesc,
            detailUrl: result.link,
            sourceName: ext.name,
            sourceUrl: ext.sourceUrl,
            extensionPackageId: ext.packageId,
            currentChapterIndex: initialChapterIndex,
            currentChapterPage: 0,
            currentChapterTitle: initialChapterTitle,
            isOnShelf: request.oldIsOnShelf,
            isHistory: request.oldIsHistory,
            host: bookHost
        )
        let chapters = tocChapters.enumerated().map { index, item in
            ChapterMetadataSnapshot(title: item.name, url: item.url, index: index, host: item.host, isSection: item.isSection)
        }
        return SourceSnapshot(createSnapshot: createSnapshot, chapters: chapters)
    }
}
