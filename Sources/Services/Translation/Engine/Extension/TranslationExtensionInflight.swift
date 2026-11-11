import Foundation

/// Gộp các lượt dịch **trùng nhau đang chạy**: Reader và TTS (hoặc Reader nạp trước chương kế cùng lúc TTS nạp trước)
/// xin dịch cùng các dòng với cùng cấu hình ⇒ chỉ một lượt gọi tiện ích, mọi bên nhận cùng kết quả. Không có bước
/// này thì hai bên cùng trượt cache, gọi tiện ích hai lần (tốn lượt) và với máy dịch kiểu AI ra hai chữ khác nhau ⇒
/// vệt highlight TTS lệch chữ Reader đang hiện.
///
/// Lượt chạy là `Task` riêng (không thừa hưởng huỷ của bên gọi). Một bên huỷ chỉ rời đi; bên cuối cùng rời đi do huỷ
/// thì lượt bị huỷ theo (không gọi tiện ích cho chương không ai cần nữa). Bên đã huỷ mà còn bên khác chờ thì vẫn chờ
/// tới khi lượt xong (kết quả bị bỏ ở phía nó).
final class TranslationExtensionInflight: @unchecked Sendable {
    static let shared = TranslationExtensionInflight()

    struct Outcome: Sendable {
        /// Bản dịch theo đúng thứ tự các dòng đã gửi; `nil` = dòng lỗi.
        let texts: [String?]
        let errorMessage: String?
        /// Có lần gọi tiện ích bị lỗi (mạng, `Response.error`, script hỏng) — khác với chỉ trả thiếu dòng.
        let hadCallError: Bool
    }

    private struct Entry {
        let task: Task<Outcome, Error>
        var waiters: Int
    }

    /// Mỗi bên chờ rời đi đúng một lần (huỷ và kết thúc có thể chạy đua nhau).
    private final class LeaveToken: @unchecked Sendable {
        private let lock = NSLock()
        private var left = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !left else { return false }
            left = true
            return true
        }
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]

    private init() {}

    func run(key: String, operation: @escaping @Sendable () async throws -> Outcome) async throws -> Outcome {
        try Task.checkCancellation()
        lock.lock()
        let task: Task<Outcome, Error>
        if var entry = entries[key] {
            entry.waiters += 1
            entries[key] = entry
            task = entry.task
        } else {
            task = Task.detached(priority: .userInitiated) { try await operation() }
            entries[key] = Entry(task: task, waiters: 1)
        }
        lock.unlock()

        let token = LeaveToken()
        do {
            let outcome = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                if token.claim() { self.leave(key: key, cancelling: true) }
            }
            if token.claim() { leave(key: key, cancelling: false) }
            try Task.checkCancellation()
            return outcome
        } catch {
            if token.claim() { leave(key: key, cancelling: Task.isCancelled) }
            throw error
        }
    }

    private func leave(key: String, cancelling: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard var entry = entries[key] else { return }
        entry.waiters -= 1
        if entry.waiters > 0 {
            entries[key] = entry
            return
        }
        entries[key] = nil
        if cancelling { entry.task.cancel() }
    }
}
