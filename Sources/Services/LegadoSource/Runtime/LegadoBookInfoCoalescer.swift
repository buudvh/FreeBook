import Foundation

/// Gộp các lượt **thông tin sách** đang chạy cho cùng một sách (khoá `LegadoBookStateStore.memoryKey`).
///
/// Trang chi tiết gọi `detail` và mục lục **song song**; với sách chưa biết `tocUrl`, mục lục phải chạy thông tin sách
/// trước. Không gộp thì trang sách bị tải hai lần và hai phiên cùng ghi trạng thái. Lượt đến sau chờ chung kết quả.
///
/// Huỷ: lượt chạy là `Task` không cấu trúc; nó chỉ bị huỷ khi **mọi** người chờ đều đã huỷ. Người chờ bị huỷ trong
/// lúc người khác còn chờ vẫn nhận kết quả khi xong (caller tự kiểm `Task.checkCancellation()` nếu cần).
final class LegadoBookInfoCoalescer: @unchecked Sendable {
    static let shared = LegadoBookInfoCoalescer()

    private struct Flight {
        let id: UUID
        let task: Task<LegadoSourceRuntime.BookInfoResult, Error>
        var waiters: Int
    }

    private let lock = NSLock()
    private var flights: [String: Flight] = [:]

    func run(
        key: String,
        operation: @escaping @Sendable () async throws -> LegadoSourceRuntime.BookInfoResult
    ) async throws -> LegadoSourceRuntime.BookInfoResult {
        let joined = join(key: key, operation: operation)
        return try await withTaskCancellationHandler {
            try await joined.task.value
        } onCancel: {
            self.leave(key: key, id: joined.id)
        }
    }

    private func join(
        key: String,
        operation: @escaping @Sendable () async throws -> LegadoSourceRuntime.BookInfoResult
    ) -> (id: UUID, task: Task<LegadoSourceRuntime.BookInfoResult, Error>) {
        lock.lock()
        defer { lock.unlock() }
        if var flight = flights[key] {
            flight.waiters += 1
            flights[key] = flight
            return (flight.id, flight.task)
        }
        let id = UUID()
        let task = Task<LegadoSourceRuntime.BookInfoResult, Error> { [weak self] in
            defer { self?.finish(key: key, id: id) }
            return try await operation()
        }
        flights[key] = Flight(id: id, task: task, waiters: 1)
        return (id, task)
    }

    /// Một người chờ huỷ: hết người chờ ⇒ huỷ lượt chạy.
    private func leave(key: String, id: UUID) {
        lock.lock()
        guard var flight = flights[key], flight.id == id else {
            lock.unlock()
            return
        }
        flight.waiters -= 1
        if flight.waiters <= 0 {
            flights.removeValue(forKey: key)
            lock.unlock()
            flight.task.cancel()
            return
        }
        flights[key] = flight
        lock.unlock()
    }

    private func finish(key: String, id: UUID) {
        lock.lock()
        if flights[key]?.id == id {
            flights.removeValue(forKey: key)
        }
        lock.unlock()
    }
}
