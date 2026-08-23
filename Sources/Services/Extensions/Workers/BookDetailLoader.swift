import Foundation



public actor BookDetailLoader {
    public static let shared = BookDetailLoader()

    private init() {}

    public func fetchDetail(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?
    ) async throws -> NovelDetailResult {
        return try await ExtensionManager.shared.detail(
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson
        )
    }

    public func fetchFirstPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?
    ) async throws -> (chapters: [ChapterResult], pages: [String]) {
        let path = snapshot.localPath
        var firstPageChapters: [ChapterResult] = []
        var pages: [String] = []

        if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
            pages = try await ExtensionManager.shared.page(
                localPath: path,
                downloadUrl: snapshot.downloadUrl,
                url: url,
                host: host,
                configJson: snapshot.configJson
            )
            if !pages.isEmpty {
                firstPageChapters = try await ExtensionManager.shared.toc(
                    localPath: path,
                    downloadUrl: snapshot.downloadUrl,
                    url: pages[0],
                    host: host,
                    configJson: snapshot.configJson
                )
            } else {
                firstPageChapters = try await ExtensionManager.shared.toc(
                    localPath: path,
                    downloadUrl: snapshot.downloadUrl,
                    url: url,
                    host: host,
                    configJson: snapshot.configJson
                )
            }
        } else {
            firstPageChapters = try await ExtensionManager.shared.toc(
                localPath: path,
                downloadUrl: snapshot.downloadUrl,
                url: url,
                host: host,
                configJson: snapshot.configJson
            )
        }

        return (firstPageChapters, pages)
    }

    /// Mục lục của **đúng một** trang đã biết url — dùng khi chỉ cần trang cuối (kiểm tra chương mới).
    public func fetchPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?
    ) async throws -> [ChapterResult] {
        return try await ExtensionManager.shared.toc(
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson
        )
    }

    public func fetchRemainingPages(
        snapshot: ExtensionExecutionSnapshot,
        pages: [String],
        host: String?,
        onPageFetched: (@Sendable (Int, Int, [ChapterResult]) async -> Void)? = nil
    ) async throws -> [ChapterResult] {
        var allChapters: [ChapterResult] = []
        let remainingPages = Array(pages.dropFirst())
        let totalPages = pages.count

        for (idx, pageUrl) in remainingPages.enumerated() {
            try Task.checkCancellation()
            let pageChaps = try await ExtensionManager.shared.toc(
                localPath: snapshot.localPath,
                downloadUrl: snapshot.downloadUrl,
                url: pageUrl,
                host: host,
                configJson: snapshot.configJson
            )
            allChapters.append(contentsOf: pageChaps)
            if let onPageFetched {
                await onPageFetched(idx + 2, totalPages, pageChaps)
            }
        }
        return allChapters
    }
}
