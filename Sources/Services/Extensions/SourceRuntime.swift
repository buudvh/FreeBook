import Foundation

/// Điểm vào runtime duy nhất cho mọi call site: định tuyến theo loại nguồn của `localPath`.
///
/// - Tiện ích JS ⇒ chuyển **nguyên tham số** sang `ExtensionManager.shared` (hành vi y hệt trước khi có facade).
/// - Nguồn Legado (`Extension.type` họ `legado*`) ⇒ engine Legado (`SourceRuntime+Legado.swift`); **không** đi qua
///   `JSExecutor.cleanAndResolveUrl` — URL của nguồn Legado đã tuyệt đối và có thể mang khối option `,{…}`.
///
/// Không gắn actor: gọi được từ mọi nơi, công việc chạy ngoài main (engine Legado chạy trên thread nền riêng).
public final class SourceRuntime: @unchecked Sendable {
    public static let shared = SourceRuntime()

    /// Tên "script" giả mà `genre` của nguồn Legado gắn vào `CategoryResult.script` cho mục khám phá;
    /// `executeCustomScript` nhận lại tên này cùng `input` = rule URL của mục để chạy luồng khám phá.
    public static let legadoExploreScriptName = "__legado_explore__"

    private init() {}

    /// `true` khi `localPath` là thư mục của một nguồn Legado đã cài (hoặc bản nháp có `plugin.json` loại `legado*`).
    /// Đồng bộ, không chặn: đọc bảng chụp có lock của kho tiện ích.
    public func isLegado(localPath: String) -> Bool {
        LegadoSourceTargetResolver.shared.isLegado(localPath: localPath)
    }

    public func search(localPath: String, downloadUrl: String = "", query: String, page: Int, configJson: String = "{}") async throws -> [ExtensionItemResult] {
        if let target = try legadoTarget(localPath) {
            return try await legadoCall("search", "query=\(query), page=\(page)") {
                try await LegadoSourceRuntime.search(target, query: query, page: page)
            }
        }
        return try await ExtensionManager.shared.search(localPath: localPath, downloadUrl: downloadUrl, query: query, page: page, configJson: configJson)
    }

    public func detail(localPath: String, downloadUrl: String = "", url: String, host: String? = nil, configJson: String = "{}", context: SourceRuntimeContext? = nil) async throws -> NovelDetailResult {
        if let target = try legadoTarget(localPath) {
            return try await legadoCall("detail", url) {
                try await LegadoSourceRuntime.detail(target, bookUrl: url, context: context)
            }
        }
        return try await ExtensionManager.shared.detail(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Nguồn Legado: một "trang" mục lục là chính URL sách — vòng `nextTocUrl` nằm **trong** `toc`.
    public func page(localPath: String, downloadUrl: String = "", url: String, host: String? = nil, configJson: String = "{}", context: SourceRuntimeContext? = nil) async throws -> [String] {
        if try legadoTarget(localPath) != nil {
            return [url]
        }
        return try await ExtensionManager.shared.page(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Nguồn Legado: `url` là URL **trang chi tiết**; `tocUrl` lấy từ trạng thái của sách hoặc chạy thông tin sách trước.
    public func toc(localPath: String, downloadUrl: String = "", url: String, host: String? = nil, configJson: String = "{}", context: SourceRuntimeContext? = nil) async throws -> [ChapterResult] {
        if let target = try legadoTarget(localPath) {
            return try await legadoCall("toc", url) {
                try await LegadoSourceRuntime.toc(target, bookUrl: url, context: context)
            }
        }
        return try await ExtensionManager.shared.toc(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Nguồn Legado tranh/video không có nội dung chữ: ném lỗi rõ ràng (media đi `comicPages`/`videoServers`).
    public func chap(localPath: String, downloadUrl: String = "", url: String, host: String? = nil, configJson: String = "{}", context: SourceRuntimeContext? = nil) async throws -> String {
        if let target = try legadoTarget(localPath) {
            guard !target.source.kind.contentKind.isMedia else {
                throw LegadoRuntimeError.mediaHasNoText(target.source.kind.label)
            }
            return try await legadoCall("chap", url) {
                try await LegadoSourceRuntime.content(target, chapterUrl: url, context: context)
            }
        }
        return try await ExtensionManager.shared.chap(localPath: localPath, downloadUrl: downloadUrl, url: url, host: host, configJson: configJson)
    }

    /// Nguồn Legado: mọi mục khám phá bấm được (`script` = `legadoExploreScriptName`, `input` = rule URL của mục).
    public func genre(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        if let target = try legadoTarget(localPath) {
            return try await legadoCall("genre", "exploreUrl") {
                try await LegadoSourceRuntime.exploreCategories(target, scriptName: Self.legadoExploreScriptName)
            }
        }
        return try await ExtensionManager.shared.genre(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
    }

    /// Nguồn Legado: luôn `[]` — mục khám phá nằm hết ở `genre` (lưới thể loại), tránh thanh tab hàng chục mục và tránh
    /// chạy JS `exploreUrl` hai lần (Khám phá gọi `home` và `genre` song song).
    public func home(localPath: String, downloadUrl: String = "", configJson: String = "{}") async throws -> [CategoryResult] {
        if try legadoTarget(localPath) != nil {
            return []
        }
        return try await ExtensionManager.shared.home(localPath: localPath, downloadUrl: downloadUrl, configJson: configJson)
    }

    /// Nguồn Legado: chỉ hiểu `scriptFileName == legadoExploreScriptName` (một trang của mục khám phá `input`); tên
    /// khác (vd thẻ thể loại của trang chi tiết, `script` rỗng) ⇒ ném lỗi rõ ràng, không thay `{0}`.
    public func executeCustomScript(localPath: String, downloadUrl: String = "", scriptFileName: String, input: String, page: Int, pageUrl: String?, configJson: String = "{}") async throws -> (results: [ExtensionItemResult], nextPage: String?) {
        if let target = try legadoTarget(localPath) {
            guard scriptFileName == Self.legadoExploreScriptName else {
                throw LegadoRuntimeError.unsupportedScript(scriptFileName)
            }
            return try await legadoCall("explore", "\(input), page=\(page)") {
                try await LegadoSourceRuntime.explorePage(target, url: input, page: page)
            }
        }
        return try await ExtensionManager.shared.executeCustomScript(localPath: localPath, downloadUrl: downloadUrl, scriptFileName: scriptFileName, input: input, page: page, pageUrl: pageUrl, configJson: configJson)
    }
}
