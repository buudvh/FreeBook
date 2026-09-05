import Foundation

/// Phân giải `payload` của `run.start` thành một `ExtensionDebugEntrypoint`, **tách hai loại thất bại**.
///
/// Vì sao tách: trước 1.3.347 hàm phân giải trả `nil` cho cả "tên entrypoint lạ" và "tên đúng nhưng
/// thiếu tham số", nên router báo `UNKNOWN_ENTRYPOINT` cho cả hai. Đo bằng client thật: `run.start` với
/// `entrypoint: "search"` mà không có `keyword` trả `UNKNOWN_ENTRYPOINT` — câu đó đẩy người viết client
/// đi kiểm danh sách script, trong khi lỗi thật nằm ở payload của họ.
///
/// Danh sách tên và tham số phải khớp `ExtensionDebugEntrypoint`; thêm entrypoint mới thì sửa cả hai.
public enum ExtensionDebugEntrypointResolver {
    public enum Resolution: Sendable {
        case resolved(ExtensionDebugEntrypoint)
        /// Không có tên, hoặc tên không thuộc allowlist. `nil` = payload không khai `entrypoint`.
        case unknownName(String?)
        /// Tên hợp lệ nhưng thiếu một tham số bắt buộc.
        case missingArgument(entrypoint: String, field: String)
    }

    public static func resolve(from payload: ExtensionDebugProtocol.Payload?) -> Resolution {
        guard let payload, let name = payload.entrypoint else { return .unknownName(nil) }

        switch name {
        case "search":
            guard let keyword = payload.keyword else { return .missingArgument(entrypoint: name, field: "keyword") }
            return .resolved(.search(keyword: keyword, page: payload.page ?? 1))
        case "detail":
            guard let url = payload.url else { return .missingArgument(entrypoint: name, field: "url") }
            return .resolved(.detail(url: url))
        case "toc":
            guard let url = payload.url else { return .missingArgument(entrypoint: name, field: "url") }
            return .resolved(.toc(url: url))
        case "chap":
            guard let url = payload.url else { return .missingArgument(entrypoint: name, field: "url") }
            return .resolved(.chap(url: url))
        case "genre":
            return .resolved(.genre)
        case "home":
            return .resolved(.home)
        case "custom":
            guard let fileName = payload.scriptFileName else {
                return .missingArgument(entrypoint: name, field: "scriptFileName")
            }
            return .resolved(.custom(
                fileName: fileName,
                input: payload.input ?? "",
                page: payload.page ?? 1,
                pageUrl: payload.pageUrl
            ))
        default:
            return .unknownName(name)
        }
    }

    /// Tên các entrypoint được phép, để câu lỗi nói ra thay vì bắt client tự đoán.
    public static let allowedNames = ["search", "detail", "toc", "chap", "genre", "home", "custom"]
}
