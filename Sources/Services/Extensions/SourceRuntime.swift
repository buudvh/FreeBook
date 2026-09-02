import Foundation

/// Bộ định tuyến giữa hai runtime nguồn truyện: extension VBook (JavaScript, `ExtensionManager`) và
/// nguồn JSON Legado (`LegadoSourceRuntime`).
///
/// Mọi tầng gọi bóc tách đi qua đây thay vì gọi thẳng `ExtensionManager`. Lý do không nhét nhánh vào
/// `ExtensionManager`: file đó đã 1 049 dòng và nằm trong baseline "chỉ được giảm" của
/// `check_architecture.py`.
///
/// Định tuyến bằng `packageId`: nguồn Legado luôn có tiền tố `legado_` — bất biến do
/// `LegadoBookSource.packageId` đặt ra. Chọn `packageId` thay vì `Extension.type` vì mọi caller đều
/// có sẵn nó (`Extension`, `ExtensionExecutionSnapshot`, `TTSExtensionInfo`), nên không phải luồn thêm
/// tham số qua các tầng.
public enum SourceRuntime {

    public static let legadoPackagePrefix = "legado_"

    public static func isLegado(type: String?) -> Bool {
        type == ExtensionType.legado
    }

    public static func isLegado(packageId: String?) -> Bool {
        packageId?.hasPrefix(legadoPackagePrefix) ?? false
    }

    // MARK: - Tìm kiếm

    public static func search(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        query: String,
        page: Int,
        configJson: String
    ) async throws -> [ExtensionItemResult] {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.search(
                localPath: localPath,
                downloadUrl: downloadUrl,
                query: query,
                page: page,
                configJson: configJson
            )
        }
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        return try await LegadoSourceRuntime.shared.search(
            source: source,
            query: query,
            page: page
        )
    }

    // MARK: - Chi tiết

    public static func detail(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        url: String,
        host: String?,
        configJson: String,
        bookId: String? = nil
    ) async throws -> NovelDetailResult {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.detail(
                localPath: localPath,
                downloadUrl: downloadUrl,
                url: url,
                host: host,
                configJson: configJson
            )
        }
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        return try await LegadoSourceRuntime.shared.bookInfo(
            source: source,
            bookUrl: url,
            bookId: bookId
        )
    }

    // MARK: - Mục lục

    public static func toc(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        url: String,
        host: String?,
        configJson: String,
        bookId: String? = nil
    ) async throws -> [ChapterResult] {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.toc(
                localPath: localPath,
                downloadUrl: downloadUrl,
                url: url,
                host: host,
                configJson: configJson
            )
        }
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        return try await LegadoSourceRuntime.shared.toc(
            source: source,
            bookUrl: url,
            bookId: bookId
        )
    }

    // MARK: - Nội dung chương

    /// Định tuyến theo `packageId` vì đường đọc/TTS chỉ giữ `TTSExtensionInfo`.
    public static func chapter(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        url: String,
        host: String?,
        configJson: String,
        bookId: String? = nil,
        chapterIndex: Int? = nil,
        chapterTitle: String? = nil,
        bookUrl: String? = nil
    ) async throws -> String {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.chap(
                localPath: localPath,
                downloadUrl: downloadUrl,
                url: url,
                host: host,
                configJson: configJson
            )
        }
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        return try await LegadoSourceRuntime.shared.content(
            source: source,
            chapterUrl: url,
            chapterTitle: chapterTitle,
            chapterIndex: chapterIndex,
            bookUrl: bookUrl,
            bookId: bookId
        )
    }

    // MARK: - Khám phá

    public static func home(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String
    ) async throws -> [CategoryResult] {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.home(
                localPath: localPath,
                downloadUrl: downloadUrl,
                configJson: configJson
            )
        }
        // Nguồn Legado không có khái niệm "tab trang chủ" riêng, nhưng `exploreUrl` của nó đúng là một
        // danh sách mục để lướt — nên dùng nó làm **home** để được UI tab vuốt ngang, và trả `[]` ở
        // `genre` để cùng danh sách không hiện hai lần.
        return try await exploreCategories(localPath: localPath)
    }

    public static func genre(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String
    ) async throws -> [CategoryResult] {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.genre(
                localPath: localPath,
                downloadUrl: downloadUrl,
                configJson: configJson
            )
        }
        return []
    }

    private static func exploreCategories(localPath: String) async throws -> [CategoryResult] {
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        let kinds = try await LegadoSourceRuntime.shared.exploreKinds(source: source)
        guard !kinds.isEmpty else {
            throw LegadoRuntimeError.missingRule("exploreUrl")
        }
        return kinds
    }

    /// Chạy một mục Khám Phá. Với VBook là script tuỳ chọn (`gen.js`…), với Legado là URL của mục.
    public static func categoryPage(
        packageId: String,
        localPath: String,
        downloadUrl: String,
        scriptFileName: String,
        input: String,
        page: Int,
        pageUrl: String?,
        configJson: String
    ) async throws -> (results: [ExtensionItemResult], nextPage: String?) {
        guard isLegado(packageId: packageId) else {
            return try await ExtensionManager.shared.executeCustomScript(
                localPath: localPath,
                downloadUrl: downloadUrl,
                scriptFileName: scriptFileName,
                input: input,
                page: page,
                pageUrl: pageUrl,
                configJson: configJson
            )
        }
        let source = try await LegadoSourceStore.shared.source(atLocalPath: localPath)
        let results = try await LegadoSourceRuntime.shared.explore(
            source: source,
            input: input,
            page: page
        )
        // Nguồn Legado phân trang bằng `{{page}}` trong URL nên không có con trỏ trang riêng.
        return (results, nil)
    }
}
