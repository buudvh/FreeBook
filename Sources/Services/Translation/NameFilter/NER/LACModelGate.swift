import Foundation

/// Gộp các lượt `LACModel.prepare` và giữ bộ gán nhãn **yếu**.
///
/// - Bộ gán nhãn cũ còn sống (bộ lọc nào đó đang giữ) ⇒ trả ngay, không báo tiến độ.
/// - Nhiều lượt gọi cùng lúc ⇒ **một** lượt tải + nạp + tự kiểm (`LACModel.load`), tiến độ phát cho mọi người chờ, kết
///   quả trả cho tất cả.
/// - Huỷ (cùng luật "Huỷ vs flush" của repo): người chờ bị huỷ chỉ nhận `CancellationError` cho riêng mình; lượt gốc chỉ
///   dừng khi người chờ **cuối cùng** rời đi. Lượt mới sau đó đợi lượt vừa huỷ dừng hẳn rồi mới đụng tới thư mục model.
///
/// Dùng khoá thay vì actor để báo tiến độ đồng bộ, đúng thứ tự (một actor phải đẩy từng lần báo qua `Task`, tới tay người
/// nghe sai thứ tự được).
final class LACModelGate: @unchecked Sendable {
    static let shared = LACModelGate()

    private struct Waiter {
        let continuation: CheckedContinuation<LACTagger, Error>
        let progress: @Sendable (Double?) -> Void
    }

    private let lock = NSLock()
    /// Giữ cho các lần báo tiến độ tới tay người nghe đúng thứ tự đã tính (giữ suốt lúc gọi callback; `lock` thì không).
    private let deliveryLock = NSLock()
    private weak var cached: LACTagger?
    private var waiters: [UUID: Waiter] = [:]
    private var running: Task<Void, Never>?
    private var windingDown: Task<Void, Never>?
    private var generation = 0
    private var lastFraction = -1.0
    private var reportedLoading = false

    private init() {}

    func tagger(progress: @escaping @Sendable (Double?) -> Void) async throws -> LACTagger {
        lock.lock()
        let alive = cached
        lock.unlock()
        if let alive { return alive }

        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<LACTagger, Error>) in
                self.join(id: id, progress: progress, continuation: continuation)
            }
        } onCancel: {
            self.leave(id: id)
        }
    }

    /// Đăng ký trước rồi mới xét huỷ: huỷ tới trước lúc đăng ký thì `leave` lúc đó không thấy ai, lần xét ở cuối bắt lại.
    private func join(
        id: UUID,
        progress: @escaping @Sendable (Double?) -> Void,
        continuation: CheckedContinuation<LACTagger, Error>
    ) {
        lock.lock()
        if let alive = cached {
            lock.unlock()
            continuation.resume(returning: alive)
            return
        }
        waiters[id] = Waiter(continuation: continuation, progress: progress)
        if running == nil { startLocked() }
        lock.unlock()
        if Task.isCancelled { leave(id: id) }
    }

    private func startLocked() {
        generation += 1
        let token = generation
        let previous = windingDown
        windingDown = nil
        lastFraction = -1
        reportedLoading = false
        running = Task.detached(priority: .userInitiated) {
            await previous?.value
            let result: Result<LACTagger, Error>
            do {
                result = .success(try await LACModel.load(progress: { value in
                    self.report(value, token: token)
                }))
            } catch {
                result = .failure(error)
            }
            self.finish(result, token: token)
        }
    }

    private func leave(id: UUID) {
        lock.lock()
        guard let waiter = waiters.removeValue(forKey: id) else {
            lock.unlock()
            return
        }
        var abandoned: Task<Void, Never>?
        if waiters.isEmpty, let task = running {
            abandoned = task
            running = nil
            windingDown = task
        }
        lock.unlock()
        if let abandoned {
            abandoned.cancel()
            AppLogger.shared.log("🧠 [LAC] Không còn ai chờ — dừng lượt chuẩn bị model")
        }
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func finish(_ result: Result<LACTagger, Error>, token: Int) {
        lock.lock()
        guard token == generation, running != nil else {
            lock.unlock()
            return
        }
        running = nil
        let finished = Array(waiters.values)
        waiters.removeAll()
        if case .success(let tagger) = result { cached = tagger }
        lock.unlock()
        for waiter in finished {
            waiter.continuation.resume(with: result)
        }
    }

    /// Tiến độ tải chỉ tăng; sau `nil` (đang nạp) bỏ mọi số tới muộn từ KVO của URLSession.
    private func report(_ value: Double?, token: Int) {
        deliveryLock.lock()
        defer { deliveryLock.unlock() }
        lock.lock()
        guard token == generation, running != nil, !reportedLoading else {
            lock.unlock()
            return
        }
        if let value {
            guard value > lastFraction else {
                lock.unlock()
                return
            }
            lastFraction = value
        } else {
            reportedLoading = true
        }
        let callbacks = waiters.values.map(\.progress)
        lock.unlock()
        for callback in callbacks { callback(value) }
    }
}
