import Foundation

/// Lỗi của một lượt chạy script tiện ích JS (`ExtensionManager`) **kèm** URL `fetch` của lượt đó, để UI dựng nút
/// "Mở link lỗi" (`SourceErrorLink.resolve(from:fallback:host:)`).
///
/// Trong suốt với mọi chỗ đang hiện lỗi:
/// - `errorDescription` / `localizedDescription` = của lỗi gốc ⇒ chữ lỗi trên UI và trong log **không đổi**.
/// - Bridge sang `NSError` giữ lỗi gốc ở `NSUnderlyingErrorKey` (`FileDescriptorCensus.isOutOfDescriptors` /
///   `describe` vẫn thấy tầng bên trong) và `errorCode` = mã của lỗi gốc. Domain thì đổi — không chỗ nào trong
///   `Sources/` so domain của lỗi script (đã grep khi thêm lớp bọc).
/// - **Không** bao giờ bọc `CancellationError`, không bọc hai lần, và không bọc khi lượt chạy không có fetch nào
///   (`wrapping` trả nguyên lỗi) ⇒ mọi `catch is CancellationError` / so kiểu cụ thể giữ nguyên hành vi.
///
/// Code cần so kiểu lỗi gốc thì dùng `ExtensionLoadError.unwrapped(_:)`.
///
/// `description` / `debugDescription` = của lỗi gốc: nội suy `"\(error)"` trong log **không** in hai URL fetch (query có
/// thể chứa token).
struct ExtensionLoadError: LocalizedError, CustomNSError, CustomStringConvertible, CustomDebugStringConvertible {
    /// Lỗi gốc (NSError của `JSExecutor`, `ExtensionManagerError`, lỗi parse…).
    let underlying: Error
    /// URL request của `fetch` lỗi gần nhất trong lượt chạy (status cuối không 2xx).
    let failedFetchURL: String?
    /// URL request của `fetch` gần nhất (mọi status) trong lượt chạy.
    let lastFetchURL: String?

    var errorDescription: String? { underlying.localizedDescription }
    var failureReason: String? { (underlying as? LocalizedError)?.failureReason }
    var recoverySuggestion: String? { (underlying as? LocalizedError)?.recoverySuggestion }
    var description: String { String(describing: underlying) }
    var debugDescription: String { String(describing: underlying) }

    static var errorDomain: String { "FreeBook.ExtensionLoadError" }
    var errorCode: Int { (underlying as NSError).code }
    var errorUserInfo: [String: Any] {
        [
            NSLocalizedDescriptionKey: underlying.localizedDescription,
            NSUnderlyingErrorKey: underlying as NSError
        ]
    }

    /// Bọc `error` với dấu vết fetch của `executor` (gọi trong `catch` của hàm đã tạo executor). Trả **nguyên** `error`
    /// khi: là `CancellationError`, đã là `ExtensionLoadError`, không có executor, hoặc lượt chạy chưa fetch lần nào.
    static func wrapping(_ error: Error, executor: JSExecutor?) -> Error {
        if error is CancellationError || error is ExtensionLoadError { return error }
        guard let executor else { return error }
        let failed = executor.lastFailedFetchURL
        let last = executor.lastFetchURL
        guard failed != nil || last != nil else { return error }
        return ExtensionLoadError(underlying: error, failedFetchURL: failed, lastFetchURL: last)
    }

    /// Lỗi gốc nếu `error` là lớp bọc này, ngược lại chính `error`.
    static func unwrapped(_ error: Error) -> Error {
        (error as? ExtensionLoadError)?.underlying ?? error
    }
}
