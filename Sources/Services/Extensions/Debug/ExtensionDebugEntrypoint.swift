import Foundation

/// Bảy entrypoint được phép debug ở Phase 1, kèm **typed arguments**.
///
/// Danh sách này là allowlist theo Phase 0: `page` và TTS bị để ngoài MVP vì có side effect/chi phí
/// riêng (`page` gọi lồng vào `toc`, TTS sinh audio) và chưa chốt quota/cách huỷ cho chúng.
///
/// `jsArguments` phải **khớp từng ký tự** với `ExtensionManager`, kể cả những chỗ trông như lỗi:
/// `search` truyền `page` dưới dạng `String`; `toc` chỉ resolve URL khi extension **không** có script
/// `page`; custom script thay `{0}` trong input bằng số trang và truyền `pageUrl` rỗng ở trang 1. Lệch
/// một chỗ là runner debug chạy một contract khác với runtime thật, tức là mất đúng cái giá trị mà màn
/// debug tồn tại để có.
public enum ExtensionDebugEntrypoint: Sendable, Hashable {
    case search(keyword: String, page: Int)
    case detail(url: String)
    case toc(url: String)
    case chap(url: String)
    case genre
    case home
    /// Script phụ do `home`/`genre` trả về. Khác sáu ca trên: nó được resolve theo **tên file**, không
    /// qua khoá `script` trong `plugin.json` — đúng như `ExtensionManager.executeCustomScript`.
    case custom(fileName: String, input: String, page: Int, pageUrl: String?)

    public var scriptKey: String {
        switch self {
        case .search: return "search"
        case .detail: return "detail"
        case .toc: return "toc"
        case .chap: return "chap"
        case .genre: return "genre"
        case .home: return "home"
        case .custom(let fileName, _, _, _): return fileName
        }
    }

    /// `true` khi phải tìm file theo tên trong gốc extension / `src/` thay vì tra khoá `script`.
    public var resolvesByFileName: Bool {
        if case .custom = self { return true }
        return false
    }

    public var displayName: String {
        switch self {
        case .search: return "search.js — execute(keyword, page)"
        case .detail: return "detail.js — execute(url)"
        case .toc: return "toc.js — execute(url)"
        case .chap: return "chap.js — execute(url)"
        case .genre: return "genre.js — execute()"
        case .home: return "home.js — execute()"
        case .custom: return "custom — execute(input, pageUrl)"
        }
    }

    /// Mô tả input đã redact, cho event `runStarted`.
    public var inputSummary: String {
        switch self {
        case .search(let keyword, let page):
            return "keyword=\(keyword), page=\(page)"
        case .detail(let url), .toc(let url), .chap(let url):
            return ExtensionDebugRedactor.url(url)
        case .genre, .home:
            return "(không có tham số)"
        case .custom(let fileName, let input, let page, _):
            return "\(fileName), input=\(input), page=\(page)"
        }
    }

    /// Arguments truyền vào `execute(...)`. `localPath` cần cho ca `toc` vì việc resolve URL phụ thuộc
    /// extension có script `page` hay không — đúng như `ExtensionManager.toc`.
    public func jsArguments(localPath: String, host: String?) -> [Any] {
        switch self {
        case .search(let keyword, let page):
            return [keyword, String(page)]
        case .detail(let url), .chap(let url):
            return [JSExecutor.cleanAndResolveUrl(url, host: host)]
        case .toc(let url):
            let hasPageScript = ExtensionManager.shared.hasScript(localPath: localPath, scriptKey: "page")
            return [hasPageScript ? url : JSExecutor.cleanAndResolveUrl(url, host: host)]
        case .genre, .home:
            return []
        case .custom(_, let input, let page, let pageUrl):
            let formattedInput = input.replacingOccurrences(of: "{0}", with: String(page))
            return [formattedInput, page == 1 ? "" : (pageUrl ?? "")]
        }
    }

    /// Các ca mẫu để UI dựng picker; giá trị input được thay lúc chạy.
    public static var allTemplates: [ExtensionDebugEntrypoint] {
        [
            .search(keyword: "", page: 1),
            .detail(url: ""),
            .toc(url: ""),
            .chap(url: ""),
            .genre,
            .home,
            .custom(fileName: "", input: "", page: 1, pageUrl: nil)
        ]
    }

    /// Khoá dùng làm `tag` của picker. Ca custom dùng một khoá cố định vì tên file do người dùng nhập.
    public var selectionKey: String {
        if case .custom = self { return "__custom__" }
        return scriptKey
    }
}
