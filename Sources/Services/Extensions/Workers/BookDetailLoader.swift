import Foundation



public actor BookDetailLoader {
    public static let shared = BookDetailLoader()

    private init() {}

    public func fetchDetail(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        bookId: String? = nil
    ) async throws -> NovelDetailResult {
        return try await SourceRuntime.detail(
            packageId: snapshot.packageId,
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson,
            bookId: bookId
        )
    }

    public func fetchFirstPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        bookId: String? = nil
    ) async throws -> (chapters: [ChapterResult], pages: [String]) {
        let path = snapshot.localPath
        var firstPageChapters: [ChapterResult] = []
        var pages: [String] = []

        // Nguồn Legado tự lặp `nextTocUrl` bên trong runtime nên không có khái niệm script `page`.
        if !SourceRuntime.isLegado(packageId: snapshot.packageId),
           ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
            pages = try await ExtensionManager.shared.page(
                localPath: path,
                downloadUrl: snapshot.downloadUrl,
                url: url,
                host: host,
                configJson: snapshot.configJson
            )
            firstPageChapters = try await fetchPageTOC(
                snapshot: snapshot,
                url: pages.isEmpty ? url : pages[0],
                host: host,
                bookId: bookId
            )
        } else {
            firstPageChapters = try await fetchPageTOC(
                snapshot: snapshot,
                url: url,
                host: host,
                bookId: bookId
            )
        }

        return (firstPageChapters, pages)
    }

    /// Mục lục của **đúng một** trang đã biết url — dùng khi chỉ cần trang cuối (kiểm tra chương mới).
    public func fetchPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        bookId: String? = nil
    ) async throws -> [ChapterResult] {
        return try await SourceRuntime.toc(
            packageId: snapshot.packageId,
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson,
            bookId: bookId
        )
    }

    public func fetchRemainingPages(
        snapshot: ExtensionExecutionSnapshot,
        pages: [String],
        host: String?,
        bookId: String? = nil,
        onPageFetched: (@Sendable (Int, Int, [ChapterResult]) async -> Void)? = nil
    ) async throws -> [ChapterResult] {
        var allChapters: [ChapterResult] = []
        let remainingPages = Array(pages.dropFirst())
        let totalPages = pages.count

        for (idx, pageUrl) in remainingPages.enumerated() {
            try Task.checkCancellation()
            let pageChaps = try await fetchPageTOC(
                snapshot: snapshot,
                url: pageUrl,
                host: host,
                bookId: bookId
            )
            allChapters.append(contentsOf: pageChaps)
            if let onPageFetched {
                await onPageFetched(idx + 2, totalPages, pageChaps)
            }
        }
        return allChapters
    }
}
