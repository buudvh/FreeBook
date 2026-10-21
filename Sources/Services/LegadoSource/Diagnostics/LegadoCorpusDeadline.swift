import Foundation

/// Trần thời gian cho một bước của bộ nghiệm thu.
///
/// **Không** race bằng `withThrowingTaskGroup`: group chờ mọi task con kết thúc mới thoát, mà engine ghi rõ vòng lặp
/// JS thuần không ngắt được — một nguồn kẹt sẽ treo cả lượt chạy. Ở đây công việc chạy trong một `Task` riêng, hẹn
/// giờ trong một `Task` khác, và continuation được resume **đúng một lần** bởi bên về trước. Hết giờ thì huỷ task công
/// việc rồi bỏ chờ (`Exceeded.abandoned`): request mạng nhả trong ~0,1 s, còn vòng JS thuần có thể chạy tiếp ở nền.
///
/// Huỷ task gọi `run` ⇒ ném `CancellationError` ngay, cũng huỷ task công việc.
enum LegadoCorpusDeadline {
    struct Exceeded: Error, Sendable {
        let seconds: Int
    }

    static func run<T: Sendable>(
        seconds: Int,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let box = Box<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                box.install(continuation)
                let work = Task {
                    do {
                        let value = try await operation()
                        box.resolve(.success(value))
                    } catch {
                        box.resolve(.failure(error))
                    }
                }
                let timer = Task {
                    try? await Task.sleep(nanoseconds: UInt64(max(seconds, 1)) * 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    box.resolve(.failure(Exceeded(seconds: seconds)))
                }
                box.attach(work: work, timer: timer)
            }
        } onCancel: {
            box.resolve(.failure(CancellationError()))
        }
    }

    /// Cửa "resume một lần": resume hai lần một `CheckedContinuation` là crash, nên mọi đường đều qua khoá.
    final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<T, Error>?
        /// Kết quả đến **trước** khi continuation được cài (huỷ rất sớm).
        private var early: Result<T, Error>?
        private var work: Task<Void, Never>?
        private var timer: Task<Void, Never>?
        private var isResolved = false

        func install(_ newContinuation: CheckedContinuation<T, Error>) {
            lock.lock()
            if let early {
                self.early = nil
                lock.unlock()
                newContinuation.resume(with: early)
                return
            }
            continuation = newContinuation
            lock.unlock()
        }

        func attach(work newWork: Task<Void, Never>, timer newTimer: Task<Void, Never>) {
            lock.lock()
            if isResolved {
                lock.unlock()
                newWork.cancel()
                newTimer.cancel()
                return
            }
            work = newWork
            timer = newTimer
            lock.unlock()
        }

        func resolve(_ result: Result<T, Error>) {
            lock.lock()
            guard !isResolved else {
                lock.unlock()
                return
            }
            isResolved = true
            let pending = continuation
            continuation = nil
            if pending == nil {
                early = result
            }
            let runningWork = work
            let runningTimer = timer
            work = nil
            timer = nil
            lock.unlock()

            runningWork?.cancel()
            runningTimer?.cancel()
            pending?.resume(with: result)
        }
    }
}
