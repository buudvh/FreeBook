import Foundation

/// Phần tải danh mục của `DiscoveryView`, tách khỏi file gốc để giữ dưới baseline dòng. Chỉ gồm hàm tĩnh không đụng
/// state — `loadDiscoveryData` (file gốc) giữ việc huỷ lượt cũ và chặn ghi đè khi nguồn đã đổi.
extension DiscoveryView {
    /// Lỗi thật của một phần danh mục (script đã khai mà chạy lỗi): chữ lỗi + link "Mở link lỗi" (resolve ngay trong
    /// `catch`, dự phòng `sourceUrl` của nguồn).
    typealias CatalogFailure = (message: String, link: SourceErrorLink?)

    /// Tải song song `home` và `genre` của một nguồn. Có `exploreTab` ⇒ tab đó đứng đầu, các tab `home` vẫn xếp sau.
    /// Cố ý khác hợp đồng extension (khai cả hai thì `explore` thắng, `home` bị bỏ) — người dùng chọn giữ cả hai
    /// (1.3.554). Thiếu script hoặc lỗi ⇒ mảng rỗng cho phần đó; phần còn lại vẫn dùng được. `failure` chỉ có khi một
    /// phần **đã khai** chạy lỗi — màn chỉ hiện nó khi cả hai phần đều rỗng (không khai gì ⇒ `nil`, giữ câu báo thiếu).
    static func fetchCatalog(
        _ ext: Extension,
        exploreTab: CategoryResult?
    ) async -> (home: [CategoryResult], genre: [CategoryResult], failure: CatalogFailure?) {
        let localPath = ext.localPath
        let downloadUrl = ext.downloadUrl
        let configJson = ext.configJson
        let sourceUrl = ext.sourceUrl
        async let genre = fetchGenre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson, sourceUrl: sourceUrl)
        let home = await fetchHome(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson, sourceUrl: sourceUrl)
        let genreResult = await genre
        // Dùng lại đúng `exploreTab` được truyền vào: tạo tab mới sẽ đổi id và trang section bị dựng/tải lại.
        return ((exploreTab.map { [$0] } ?? []) + home.items, genreResult.items,
                preferredFailure(home: home.failure, genre: genreResult.failure))
    }

    /// Tab được chọn sau một lượt tải: tab đang xem nếu còn tồn tại → tab đã nhớ (`saved`) → tab `home` đầu tiên →
    /// tab Thể loại. Không có dữ liệu ⇒ `""`.
    static func resolveCategoryId(
        current: String,
        saved: String,
        home: [CategoryResult],
        hasGenre: Bool,
        genresTabId: String
    ) -> String {
        func isAvailable(_ id: String) -> Bool {
            guard !id.isEmpty else { return false }
            return id == genresTabId ? hasGenre : home.contains { $0.id == id }
        }
        if isAvailable(current) { return current }
        if isAvailable(saved) { return saved }
        if let first = home.first { return first.id }
        return hasGenre ? genresTabId : ""
    }

    /// Lỗi hiện khi cả hai phần đều lỗi: ưu tiên lỗi có `fetch` lỗi thật (đúng trang bị chặn), rồi lỗi `home`.
    private static func preferredFailure(home: CatalogFailure?, genre: CatalogFailure?) -> CatalogFailure? {
        if let genre, genre.link?.origin == .failedFetch, home?.link?.origin != .failedFetch { return genre }
        return home ?? genre
    }

    /// `nil` khi lỗi không đáng báo: bị huỷ, hoặc tiện ích JS không khai script `scriptKey` (`getScriptPath` ném
    /// "not defined" — nguồn thiếu `home`/`genre` là chuyện bình thường). Nguồn Legado: mọi lỗi đều là lỗi thật.
    private static func failure(of error: Error, scriptKey: String, localPath: String, sourceUrl: String) -> CatalogFailure? {
        if error is CancellationError { return nil }
        guard SourceRuntime.shared.isLegado(localPath: localPath)
                || ExtensionManager.shared.hasScript(localPath: localPath, scriptKey: scriptKey) else { return nil }
        return (error.localizedDescription, SourceErrorLink.resolve(from: error, fallback: sourceUrl))
    }

    private static func fetchHome(
        localPath: String, downloadUrl: String, configJson: String, sourceUrl: String
    ) async -> (items: [CategoryResult], failure: CatalogFailure?) {
        do {
            return (try await SourceRuntime.shared.home(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson), nil)
        } catch {
            #if DEBUG
            AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script home: \(error.localizedDescription)")
            #endif
            return ([], failure(of: error, scriptKey: "home", localPath: localPath, sourceUrl: sourceUrl))
        }
    }

    /// Nguồn Legado: danh mục khám phá chạy `exploreUrl` **một lần** trong ngữ cảnh có người dùng (người dùng đang xem —
    /// `java.startBrowserAwait` vượt chặn được trình bày) và ghi đệm mục có kiểu cho tab điều khiển (`LegadoExploreTabView`).
    private static func fetchGenre(
        localPath: String, downloadUrl: String, configJson: String, sourceUrl: String
    ) async -> (items: [CategoryResult], failure: CatalogFailure?) {
        do {
            if SourceRuntime.shared.isLegado(localPath: localPath) {
                return (try await SourceRuntime.shared.legadoExploreCatalog(localPath: localPath), nil)
            }
            return (try await SourceRuntime.shared.genre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson), nil)
        } catch {
            #if DEBUG
            AppLogger.shared.log("⚠️ [DiscoveryView] Không có hoặc lỗi chạy script genre: \(error.localizedDescription)")
            #endif
            return ([], failure(of: error, scriptKey: "genre", localPath: localPath, sourceUrl: sourceUrl))
        }
    }
}
