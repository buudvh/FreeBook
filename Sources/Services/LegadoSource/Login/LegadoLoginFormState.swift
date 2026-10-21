import Foundation

/// Trạng thái form đăng nhập trong lúc chạy JS của form (spec §10.4 bước 2–3, mục 5).
///
/// Chỉ khi phiên có đối tượng này thì ngữ cảnh JS mới có `java.upLoginData(map)` (cập nhật giá trị đang hiện trên form)
/// và `java.reLoginView()` (yêu cầu dựng lại form). Dùng trên thread engine của phiên; đọc kết quả sau khi `run` xong.
final class LegadoLoginFormState: @unchecked Sendable {
    private let lock = NSLock()
    private var currentValues: [String: String]
    private var changed = false
    private var reload = false
    private var commitRequested = false

    init(values: [String: String]) {
        currentValues = values
    }

    /// Giá trị hiện tại trên form (`result` của nút, thông tin tạm khi "Đăng nhập").
    var values: [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return currentValues
    }

    /// Có giá trị nào bị JS đổi (`java.upLoginData`).
    var valuesChanged: Bool {
        lock.lock()
        defer { lock.unlock() }
        return changed
    }

    /// JS gọi `java.reLoginView()` ⇒ form phải đánh giá lại `loginUi`.
    var needsReload: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reload
    }

    /// JS gọi `java.upLoginData()` **không tham số** (U38): lưu giá trị đang có trên form làm thông tin đăng nhập.
    var requestsCommit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return commitRequested
    }

    func update(_ updates: [String: String]) {
        lock.lock()
        for (key, value) in updates where currentValues[key] != value {
            currentValues[key] = value
            changed = true
        }
        lock.unlock()
    }

    func requestReload() {
        lock.lock()
        reload = true
        lock.unlock()
    }

    func requestCommit() {
        lock.lock()
        commitRequested = true
        lock.unlock()
    }
}
