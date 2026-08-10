import Foundation

/// Serializes remote TTS work so a prefetch window describes buffered depth,
/// not the number of simultaneous network/JavaScript synthesis operations.
internal actor RemoteTTSSynthesisCoordinator {
    internal enum Priority: Int, Sendable {
        case current = 0
        case prefetch = 1
        case nextChapter = 2
    }

    internal static let shared = RemoteTTSSynthesisCoordinator()

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Data, Error>
    }

    private struct Job {
        let key: String
        var priority: Priority
        let sequence: UInt64
        let operation: @Sendable () async throws -> Data
        var waiters: [Waiter]
    }

    private var queue: [Job] = []
    private var activeJob: Job?
    private var activeTask: Task<Void, Never>?
    private var nextSequence: UInt64 = 0

    internal init() {}

    internal func synthesize(
        key: String,
        priority: Priority,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let waiterID = UUID()

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                enqueue(
                    key: key,
                    priority: priority,
                    operation: operation,
                    waiter: Waiter(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancel(waiterID: waiterID)
            }
        }
    }

    internal func cancelAll() {
        let cancellation = CancellationError()
        for job in queue {
            for waiter in job.waiters {
                waiter.continuation.resume(throwing: cancellation)
            }
        }
        queue.removeAll()

        if var activeJob {
            for waiter in activeJob.waiters {
                waiter.continuation.resume(throwing: cancellation)
            }
            activeJob.waiters.removeAll()
            self.activeJob = activeJob
        }
        activeTask?.cancel()
    }

    private func enqueue(
        key: String,
        priority: Priority,
        operation: @escaping @Sendable () async throws -> Data,
        waiter: Waiter
    ) {
        if var activeJob, activeJob.key == key, !activeJob.waiters.isEmpty {
            activeJob.waiters.append(waiter)
            self.activeJob = activeJob
            return
        }

        if let index = queue.firstIndex(where: { $0.key == key }) {
            queue[index].waiters.append(waiter)
            if priority.rawValue < queue[index].priority.rawValue {
                queue[index].priority = priority
            }
            sortQueue()
            return
        }

        nextSequence &+= 1
        queue.append(
            Job(
                key: key,
                priority: priority,
                sequence: nextSequence,
                operation: operation,
                waiters: [waiter]
            )
        )
        sortQueue()
        startNextIfNeeded()
    }

    private func sortQueue() {
        queue.sort {
            if $0.priority.rawValue == $1.priority.rawValue {
                return $0.sequence < $1.sequence
            }
            return $0.priority.rawValue < $1.priority.rawValue
        }
    }

    private func startNextIfNeeded() {
        guard activeJob == nil, !queue.isEmpty else { return }

        let job = queue.removeFirst()
        activeJob = job
        let operation = job.operation
        let key = job.key

        activeTask = Task {
            let result: Result<Data, Error>
            do {
                result = .success(try await operation())
            } catch {
                result = .failure(error)
            }
            self.complete(key: key, result: result)
        }
    }

    private func complete(key: String, result: Result<Data, Error>) {
        guard let completedJob = activeJob, completedJob.key == key else { return }

        activeJob = nil
        activeTask = nil
        for waiter in completedJob.waiters {
            waiter.continuation.resume(with: result)
        }
        startNextIfNeeded()
    }

    private func cancel(waiterID: UUID) {
        for index in queue.indices {
            if let waiterIndex = queue[index].waiters.firstIndex(where: { $0.id == waiterID }) {
                let waiter = queue[index].waiters.remove(at: waiterIndex)
                waiter.continuation.resume(throwing: CancellationError())
                if queue[index].waiters.isEmpty {
                    queue.remove(at: index)
                }
                return
            }
        }

        guard var activeJob,
              let waiterIndex = activeJob.waiters.firstIndex(where: { $0.id == waiterID }) else { return }

        let waiter = activeJob.waiters.remove(at: waiterIndex)
        waiter.continuation.resume(throwing: CancellationError())
        self.activeJob = activeJob

        if activeJob.waiters.isEmpty {
            activeTask?.cancel()
        }
    }
}
