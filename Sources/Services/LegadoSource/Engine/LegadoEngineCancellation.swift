import Foundation

/// Cờ huỷ của một phiên engine, an toàn đa luồng.
///
/// `Task` bị huỷ ⇒ `withTaskCancellationHandler` gọi `cancel()` từ luồng bất kỳ: cờ bật, mọi handler đã đăng ký (huỷ
/// `URLSessionTask`, nhả WebView) chạy ngay. Mọi chỗ chờ trên thread engine (HTTP, rate limiter, WebView, `Thread.sleep`
/// của JS) chờ theo **lát ngắn** và kiểm cờ, nên huỷ có hiệu lực trong vòng ~0,1 giây. Vòng lặp JS thuần (không gọi
/// hàm bridge) thì không ngắt được bằng API công khai của JavaScriptCore.
final class LegadoEngineCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var handlers: [Int: () -> Void] = [:]
    private var nextHandlerId = 0

    private static let slice: TimeInterval = 0.1

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        if cancelled {
            lock.unlock()
            return
        }
        cancelled = true
        let pending = Array(handlers.values)
        handlers.removeAll()
        lock.unlock()
        for handler in pending {
            handler()
        }
    }

    /// Đăng ký việc cần làm khi huỷ. Đã huỷ rồi ⇒ chạy `handler` ngay và trả `nil`.
    @discardableResult
    func register(_ handler: @escaping () -> Void) -> Int? {
        lock.lock()
        if cancelled {
            lock.unlock()
            handler()
            return nil
        }
        nextHandlerId += 1
        let id = nextHandlerId
        handlers[id] = handler
        lock.unlock()
        return id
    }

    func unregister(_ id: Int?) {
        guard let id else { return }
        lock.lock()
        handlers.removeValue(forKey: id)
        lock.unlock()
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }

    /// Ngủ có kiểm cờ huỷ (không dùng trên main thread).
    func sleep(_ seconds: TimeInterval) throws {
        var remaining = seconds
        while remaining > 0 {
            try check()
            let step = min(remaining, Self.slice)
            Thread.sleep(forTimeInterval: step)
            remaining -= step
        }
        try check()
    }

    /// Chờ semaphore tối đa `timeout` giây. `true` = được signal, `false` = hết giờ. Ném `CancellationError` khi bị huỷ.
    /// Chỉ gọi trên thread engine — **không bao giờ** trên main thread.
    func wait(_ semaphore: DispatchSemaphore, timeout: TimeInterval) throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if semaphore.wait(timeout: .now() + Self.slice) == .success { return true }
            try check()
            if Date() >= deadline { return false }
        }
    }
}
