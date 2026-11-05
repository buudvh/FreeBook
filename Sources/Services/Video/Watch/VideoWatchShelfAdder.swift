import Foundation
import SwiftData

/// "Thêm vào kệ" ở menu `⋮` của một phim **đề xuất** trên màn xem — phim chưa mở nên chưa có `VideoWatchModel`.
///
/// Cùng quy tắc định danh với màn xem (`VideoWatchRequest.resolveBookId`): phim đã có `Book` ⇒ chỉ bật cờ kệ; chưa có ⇒
/// tải chi tiết (tên, tác giả, giới thiệu — lỗi thì dùng tên / bìa của item) + **đủ** mục lục (`fetchFullTOC`) rồi tạo
/// `Book` trên kệ qua `ChapterContentRepository.saveChapterList(.replaceFullTOC)`, như nút "Thêm vào kệ" của Chi tiết.
/// Toast thuộc View: trả `Outcome`.
@MainActor
enum VideoWatchShelfAdder {
    enum Outcome: Equatable {
        case added
        case alreadyOnShelf
        case failed(String)
    }

    static func add(_ request: VideoWatchRequest, modelContainer: ModelContainer) async -> Outcome {
        let context = modelContainer.mainContext
        let bookId = request.resolveBookId(in: context)
        if let book = fetchBook(bookId: bookId, in: context) {
            guard !book.isOnShelf else { return .alreadyOnShelf }
            if case .failure(let error) = BookTransactionCoordinator.shared.setOnShelf(bookId: bookId, isOnShelf: true, in: context) {
                AppLogger.shared.log("❌ [VideoWatch] Không thêm được phim đề xuất vào kệ: \(error.localizedDescription)")
                return .failed(error.localizedDescription)
            }
            return .added
        }

        guard let ext = ExtensionLibraryRepository.shared.catalogExtension(packageId: request.packageId), !ext.localPath.isEmpty else {
            AppLogger.shared.log("❌ [VideoWatch] Thêm phim đề xuất vào kệ: tiện ích chưa cài (\(request.packageId))")
            return .failed("Tiện ích của phim này chưa được cài.")
        }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let host = ExtensionHostResolver.nonEmpty(request.host) ?? ext.sourceUrl
        let runtimeContext = SourceRuntimeContext(
            bookId: bookId,
            bookUrl: request.detailUrl,
            bookName: request.title,
            bookAuthor: nil,
            isInteractive: true
        )
        do {
            // Chi tiết chỉ để điền metadata: lỗi thì vẫn tạo bằng tên / bìa của item.
            let detail = try? await BookDetailLoader.shared.fetchDetail(snapshot: snapshot, url: request.detailUrl, host: host, context: runtimeContext)
            let (chapters, _) = try await BookDetailLoader.shared.fetchFullTOC(snapshot: snapshot, url: request.detailUrl, host: host, context: runtimeContext)
            let createSnapshot = makeCreateSnapshot(
                bookId: bookId,
                request: request,
                detail: detail,
                firstEpisodeTitle: chapters.first(where: { !$0.isSection })?.name ?? "",
                sourceUrl: ext.sourceUrl,
                host: host
            )
            _ = try await ChapterContentRepository.shared.saveChapterList(
                bookId: bookId,
                createSnapshot: createSnapshot,
                chapters: VideoWatchModel.metadata(from: chapters),
                mode: .replaceFullTOC,
                protectedTTSChapter: VideoWatchModel.activeTTSProtectedChapter
            )
            AppLogger.shared.log("🎬 [VideoWatch] Thêm phim đề xuất vào kệ (\(chapters.count) tập, bookId=\(bookId))")
            return .added
        } catch {
            if error is CancellationError { return .failed("Đã huỷ.") }
            AppLogger.shared.log("❌ [VideoWatch] Không thêm được phim đề xuất vào kệ: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    private static func fetchBook(bookId: String, in context: ModelContext) -> Book? {
        var descriptor = FetchDescriptor<Book>(predicate: #Predicate<Book> { $0.bookId == bookId })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private static func makeCreateSnapshot(
        bookId: String,
        request: VideoWatchRequest,
        detail: NovelDetailResult?,
        firstEpisodeTitle: String,
        sourceUrl: String,
        host: String
    ) -> TOCBookCreateSnapshot {
        let description = detail?.description.cleanHTML() ?? ""
        let extra = detail?.detail.cleanHTML() ?? ""
        let title = detail.map(\.name).flatMap { $0.isEmpty ? nil : $0 } ?? request.title ?? ""
        let cover = detail.map(\.cover).flatMap { $0.isEmpty ? nil : $0 } ?? request.coverUrl ?? ""
        return TOCBookCreateSnapshot(
            bookId: bookId,
            title: title,
            author: detail?.author ?? "",
            coverUrl: cover,
            desc: extra.isEmpty ? description : "\(description)\n\n---\n\(extra)",
            detailUrl: request.detailUrl,
            sourceName: request.sourceName,
            sourceUrl: sourceUrl.isEmpty ? request.detailUrl : sourceUrl,
            extensionPackageId: request.packageId,
            currentChapterIndex: 0,
            currentChapterPage: 0,
            currentChapterTitle: firstEpisodeTitle,
            isOnShelf: true,
            isHistory: false,
            host: host.isEmpty ? nil : host
        )
    }
}
