import Foundation

enum CancellableTranslationWork {
    static func run<Value: Sendable>(
        priority: TaskPriority = .userInitiated,
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let worker = Task.detached(priority: priority) {
            try Task.checkCancellation()
            let value = try await operation()
            try Task.checkCancellation()
            return value
        }
        return try await withTaskCancellationHandler {
            let value = try await worker.value
            try Task.checkCancellation()
            return value
        } onCancel: {
            worker.cancel()
        }
    }
}
