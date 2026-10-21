import Foundation

/// Một yêu cầu UI đang chờ trong `LegadoPresentationEventCenter`: sự kiện cần trình bày + chỗ nhận kết quả.
/// Thread engine chờ `semaphore` (theo lát, có kiểm huỷ — `LegadoEngineCancellation.wait`), **không bao giờ** trên main.
final class LegadoPresentationTicket: @unchecked Sendable {
    let id: UUID
    let event: LegadoPresentationEvent
    let semaphore = DispatchSemaphore(value: 0)
    /// Chạy (ngoài khoá của center) khi yêu cầu kết thúc — dùng cho `startBrowser` không chờ: gộp cookie khi đóng.
    let onFinish: (@Sendable (LegadoPresentationTicket) -> Void)?

    private let lock = NSLock()
    private var browser: LegadoBrowserResult?
    private var code: String?
    private var done = false

    init(id: UUID, event: LegadoPresentationEvent, onFinish: (@Sendable (LegadoPresentationTicket) -> Void)? = nil) {
        self.id = id
        self.event = event
        self.onFinish = onFinish
    }

    var browserResult: LegadoBrowserResult? {
        lock.lock()
        defer { lock.unlock() }
        return browser
    }

    var verificationCode: String? {
        lock.lock()
        defer { lock.unlock() }
        return code
    }

    var isFinished: Bool {
        lock.lock()
        defer { lock.unlock() }
        return done
    }

    /// `true` nếu lần gọi này kết thúc yêu cầu (lần sau bỏ qua).
    func finish(browser result: LegadoBrowserResult?, code value: String?) -> Bool {
        lock.lock()
        guard !done else {
            lock.unlock()
            return false
        }
        done = true
        browser = result
        code = value
        lock.unlock()
        semaphore.signal()
        return true
    }
}
