import Foundation

/// Tải chi tiết + mục lục qua `SourceRuntime` (tiện ích JS hay nguồn Legado đều đi một cửa).
///
/// `context` (tuỳ chọn, mặc định `nil`): caller biết sách nào (bookId, URL chi tiết…) thì truyền vào — nguồn Legado
/// ghi/đọc trạng thái theo `context.bookId`, nên id phải là id sách được/sẽ được lưu. Tiện ích JS bỏ qua tham số này.
/// Nguồn Legado không có `page.js` (`hasScript` = false) ⇒ mục lục đi thẳng từ URL chi tiết.
public actor BookDetailLoader {
    public static let shared = BookDetailLoader()

    private init() {}

    public func fetchDetail(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        context: SourceRuntimeContext? = nil
    ) async throws -> NovelDetailResult {
        return try await SourceRuntime.shared.detail(
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson,
            context: context
        )
    }

    /// Chỉ chạy `page.js` để lấy danh sách url trang mục lục — **không** tải mục lục trang nào.
    /// Trả `[]` khi extension không có script phân trang.
    public func fetchPageList(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        context: SourceRuntimeContext? = nil
    ) async throws -> [String] {
        guard ExtensionManager.shared.hasScript(localPath: snapshot.localPath, scriptKey: "page") else {
            return []
        }
        return try await SourceRuntime.shared.page(
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson,
            context: context
        )
    }

    public func fetchFirstPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        context: SourceRuntimeContext? = nil
    ) async throws -> (chapters: [ChapterResult], pages: [String]) {
        let path = snapshot.localPath
        var firstPageChapters: [ChapterResult] = []
        var pages: [String] = []

        if ExtensionManager.shared.hasScript(localPath: path, scriptKey: "page") {
            pages = try await SourceRuntime.shared.page(
                localPath: path,
                downloadUrl: snapshot.downloadUrl,
                url: url,
                host: host,
                configJson: snapshot.configJson,
                context: context
            )
            if !pages.isEmpty {
                firstPageChapters = try await SourceRuntime.shared.toc(
                    localPath: path,
                    downloadUrl: snapshot.downloadUrl,
                    url: pages[0],
                    host: host,
                    configJson: snapshot.configJson,
                    context: context
                )
            } else {
                firstPageChapters = try await SourceRuntime.shared.toc(
                    localPath: path,
                    downloadUrl: snapshot.downloadUrl,
                    url: url,
                    host: host,
                    configJson: snapshot.configJson,
                    context: context
                )
            }
        } else {
            firstPageChapters = try await SourceRuntime.shared.toc(
                localPath: path,
                downloadUrl: snapshot.downloadUrl,
                url: url,
                host: host,
                configJson: snapshot.configJson,
                context: context
            )
        }

        try Self.requireChapters(firstPageChapters, page: 1, of: max(pages.count, 1))
        return (firstPageChapters, pages)
    }

    /// Toàn bộ mục lục theo **một** quy tắc cho mọi nơi (kéo làm mới, làm mới trong Reader, đổi nguồn): `page.js`
    /// (nếu có) → trang đầu là `pages.first`, `page.js` trả rỗng thì dùng chính `url` chi tiết (truyện một trang) →
    /// các trang còn lại. Trang nào rỗng ⇒ ném lỗi, không bao giờ trả mục lục thiếu để caller ghi đè bản đã lưu.
    public func fetchFullTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        context: SourceRuntimeContext? = nil
    ) async throws -> (chapters: [ChapterResult], pages: [String]) {
        let pages = try await fetchPageList(snapshot: snapshot, url: url, host: host, context: context)
        let first = try await fetchPageTOC(snapshot: snapshot, url: pages.first ?? url, host: host, context: context)
        try Self.requireChapters(first, page: 1, of: max(pages.count, 1))
        guard pages.count > 1 else { return (first, pages) }
        let rest = try await fetchRemainingPages(snapshot: snapshot, pages: pages, host: host, context: context)
        return (first + rest, pages)
    }

    /// Một trang mục lục không có chương nào (trang chặn/captcha, bóc tách hỏng) là **lỗi**, không phải "hết chương":
    /// mảng rỗng/thiếu đi tiếp sẽ làm caller xoá mục lục đã lưu hoặc lệch chỉ số mọi chương của các trang sau.
    /// Ngoại lệ: **trang cuối** của mục lục nhiều trang được phép rỗng (`page.js` hay thừa một trang) — sau nó không
    /// còn trang nào để lệch chỉ số; nếu không, cả truyện sẽ không làm mới/tải thêm/dò chương mới được nữa.
    public static func requireChapters(_ chapters: [ChapterResult], page: Int, of totalPages: Int) throws {
        guard chapters.isEmpty else { return }
        if totalPages > 1 && page == totalPages {
            AppLogger.shared.log("⚠️ [BookDetailLoader] Trang mục lục cuối \(page)/\(totalPages) rỗng, bỏ qua")
            return
        }
        let message = totalPages > 1 ? "Trang mục lục \(page)/\(totalPages) không có chương nào" : "Nguồn trả về mục lục trống"
        AppLogger.shared.log("❌ [BookDetailLoader] \(message)")
        throw ExtensionManagerError.sourceResponse(message: message)
    }

    /// Mục lục của **đúng một** trang đã biết url — dùng khi chỉ cần trang cuối (kiểm tra chương mới).
    public func fetchPageTOC(
        snapshot: ExtensionExecutionSnapshot,
        url: String,
        host: String?,
        context: SourceRuntimeContext? = nil
    ) async throws -> [ChapterResult] {
        return try await SourceRuntime.shared.toc(
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            url: url,
            host: host,
            configJson: snapshot.configJson,
            context: context
        )
    }

    /// Các trang sau trang 1. `loadedCount` = số trang sau trang 1 đã có sẵn ở caller (lượt "Tải thêm chương" trước
    /// đó lỗi/huỷ giữa chừng) ⇒ chỉ tải tiếp phần còn thiếu.
    public func fetchRemainingPages(
        snapshot: ExtensionExecutionSnapshot,
        pages: [String],
        host: String?,
        skippingLoaded loadedCount: Int = 0,
        context: SourceRuntimeContext? = nil,
        onPageFetched: (@Sendable (Int, Int, [ChapterResult]) async -> Void)? = nil
    ) async throws -> [ChapterResult] {
        var allChapters: [ChapterResult] = []
        let totalPages = pages.count

        for pageIndex in min(1 + max(loadedCount, 0), totalPages)..<totalPages {
            try Task.checkCancellation()
            let pageChaps = try await SourceRuntime.shared.toc(
                localPath: snapshot.localPath,
                downloadUrl: snapshot.downloadUrl,
                url: pages[pageIndex],
                host: host,
                configJson: snapshot.configJson,
                context: context
            )
            try Self.requireChapters(pageChaps, page: pageIndex + 1, of: totalPages)
            allChapters.append(contentsOf: pageChaps)
            if let onPageFetched {
                await onPageFetched(pageIndex + 1, totalPages, pageChaps)
            }
        }
        return allChapters
    }
}
