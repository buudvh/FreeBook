import Foundation

/// Dấu vết `fetch` của **một lượt chạy** script (`JSExecutor.fetchTrace`): URL request gần nhất và URL request lỗi gần
/// nhất, để lỗi của lượt đó mang được "trang đã gây lỗi" lên UI (`ExtensionLoadError` → `SourceErrorLink`, nút
/// "Mở link lỗi").
///
/// - Ghi ở **một** chỗ: cuối `_nativeSyncFetch` **sau** fallback browser ẩn (status cuối cùng mà script nhận). Nhánh
///   tên miền bị chặn (403) **không** ghi (tên miền chặn sẵn, thường là quảng cáo — không phải trang nên mở), cũng như
///   nhánh URL không hợp lệ (400) và nhánh huỷ (499) — không có trang để mở.
/// - "Lỗi" = status cuối không thuộc 2xx (browser ẩn cứu được ⇒ 200 ⇒ không tính là lỗi).
/// - Ghi **URL request** (không phải URL cuối sau chuyển hướng): mở lại trong trình duyệt thì trình duyệt tự đi theo
///   chuyển hướng / trang thử thách.
/// - Xoá ở `beginExecution()` để executor dùng lại (tải truyện, TTS, ảnh comic) không rò URL của lượt trước.
///
/// URL có thể mang query chứa token ⇒ **không** log giá trị ở đây.
final class JSFetchTrace: @unchecked Sendable {
    private let lock = NSLock()
    private var failedURL: String?
    private var lastURL: String?

    /// URL request của `fetch` lỗi gần nhất trong lượt chạy hiện tại; `nil` ⇒ chưa có fetch lỗi.
    var lastFailedFetchURL: String? {
        lock.lock()
        defer { lock.unlock() }
        return failedURL
    }

    /// URL request của `fetch` gần nhất (mọi status) trong lượt chạy hiện tại; `nil` ⇒ chưa fetch lần nào.
    var lastFetchURL: String? {
        lock.lock()
        defer { lock.unlock() }
        return lastURL
    }

    /// Ghi một fetch đã có kết quả cuối. URL rỗng ⇒ bỏ qua.
    func record(url: String, status: Int) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        lock.lock()
        lastURL = trimmed
        if !(200...299).contains(status) {
            failedURL = trimmed
        }
        lock.unlock()
    }

    /// Xoá dấu vết — đầu mỗi lượt chạy.
    func reset() {
        lock.lock()
        failedURL = nil
        lastURL = nil
        lock.unlock()
    }
}

extension JSExecutor {
    /// URL request của `fetch` lỗi gần nhất trong lượt chạy hiện tại (xem `JSFetchTrace`).
    public var lastFailedFetchURL: String? { fetchTrace.lastFailedFetchURL }

    /// URL request của `fetch` gần nhất (mọi status) trong lượt chạy hiện tại (xem `JSFetchTrace`).
    public var lastFetchURL: String? { fetchTrace.lastFetchURL }

    /// Hook cuối `_nativeSyncFetch`: ghi theo `status` của response **cuối cùng** script nhận. Trả lại `response` để
    /// call site chỉ cần một dòng.
    internal func tracingFetch(_ response: [String: Any], requestURL: String) -> [String: Any] {
        fetchTrace.record(url: requestURL, status: response["status"] as? Int ?? 0)
        return response
    }
}
