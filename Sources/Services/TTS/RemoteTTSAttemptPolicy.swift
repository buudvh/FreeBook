import Foundation

/// Chính sách **một lượt tổng hợp TTS online** (Google Cloud TTS / TTS tiện ích): số lượt thử, timeout mỗi lượt, lỗi
/// nào đáng thử lại và nghỉ bao lâu giữa hai lượt.
///
/// Thử lại chỉ nằm ở **một tầng** (1.3.960): `RemoteTTSSynthesisCoordinator` áp chính sách này lúc chạy job.
/// Trước đó (1.3.953) vòng thử lại nằm trong closure của từng bên gọi, nên lượt `.current` gộp vào job nạp trước cùng
/// khoá chạy theo chính sách của lượt nạp trước (một lượt, không thử lại), còn `GoogleTTSService` lại tự thử thêm
/// 2 lượt bên trong mỗi lượt ⇒ tới 8 request cho một đoạn.
enum RemoteTTSAttemptPolicy {
    /// Nghỉ giữa hai lượt thử; server gửi `Retry-After` thì theo nó, tối đa `maximumRetryDelay`.
    static let retryDelay: TimeInterval = 0.4
    static let maximumRetryDelay: TimeInterval = 2.0

    /// Số lượt thử của job theo mức ưu tiên **hiện tại** của nó (`TTSOnlineSynthesisSettings`): đoạn đang đọc theo cấu
    /// hình, lượt nạp trước một lần (có giọng dự phòng thì thêm một lần thử lại), chương kế / lượt thử online lúc đang
    /// đọc dự phòng một lần.
    static func attempts(for priority: RemoteTTSSynthesisCoordinator.Priority) -> Int {
        let retries: Int
        switch priority {
        case .current: retries = TTSOnlineSynthesisSettings.effectiveRetryCount
        case .prefetch: retries = TTSOnlineSynthesisSettings.prefetchRetryCount
        case .nextChapter: retries = 0
        }
        return 1 + max(0, retries)
    }

    /// Timeout mỗi lượt thử (giây).
    static var timeoutSeconds: TimeInterval {
        TimeInterval(TTSOnlineSynthesisSettings.effectiveTimeoutSeconds)
    }

    /// Lỗi có đáng thử lại không. Thử lại **mọi lỗi** (như 1.3.953) **trừ** các lỗi chắc chắn lặp lại y hệt (plan rà
    /// soát 1.3.960): thiếu API key / văn bản trống / URL hỏng, HTTP 400 / 401 / 403 / 404, base64 hỏng của tiện ích,
    /// và lượt bị chính app huỷ.
    static func isRetryable(_ error: Error) -> Bool {
        if error is CancellationError { return false }
        if error is TTSSynthesisTimeoutError { return true }
        let nsError = error as NSError
        switch nsError.domain {
        case NSURLErrorDomain:
            return nsError.code != NSURLErrorCancelled
        case "GoogleTTSService":
            return ![-1, -2, -3, 400, 401, 403, 404].contains(nsError.code)
        case "ExtTTSService":
            return nsError.code != -20
        default:
            return true
        }
    }

    /// Nghỉ trước lượt thử kế: `Retry-After` của server (Google đưa vào `userInfo["retryAfterSeconds"]`) nếu dài hơn.
    static func delay(after error: Error) -> TimeInterval {
        let retryAfter = ((error as NSError).userInfo["retryAfterSeconds"] as? Double) ?? 0
        return min(maximumRetryDelay, max(retryDelay, retryAfter))
    }

    /// Chạy `operation` với giới hạn thời gian (1.3.953). Hết giờ ⇒ huỷ Task con (huỷ luôn request mạng / lệnh JS đang
    /// chờ) rồi ném `TTSSynthesisTimeoutError`. `seconds <= 0` ⇒ không giới hạn.
    static func withTimeout(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        guard seconds > 0 else { return try await operation() }
        return try await withThrowingTaskGroup(of: Data.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TTSSynthesisTimeoutError.timedOut(seconds: Int(seconds.rounded()))
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    /// Một job của `RemoteTTSSynthesisCoordinator`: mỗi lượt có timeout riêng, lỗi đáng thử lại thì nghỉ rồi thử tiếp.
    /// `allowedAttempts` được hỏi lại sau **mỗi** lượt hụt (mức ưu tiên của job có thể đã được nâng giữa chừng). Không
    /// ném: kết quả (kể cả `CancellationError`) trả về để coordinator chia cho mọi người chờ.
    static func run(
        engine: String,
        operation: @escaping @Sendable () async throws -> Data,
        allowedAttempts: @Sendable () async -> Int
    ) async -> Result<Data, Error> {
        var attempt = 0
        while true {
            attempt += 1
            do {
                return .success(try await withTimeout(seconds: timeoutSeconds, operation: operation))
            } catch is CancellationError {
                return .failure(CancellationError())
            } catch {
                let allowed = await allowedAttempts()
                guard !Task.isCancelled, attempt < allowed, isRetryable(error) else { return .failure(error) }
                AppLogger.shared.log(
                    "⚠️ [RemoteTTS] Thử lại lượt \(attempt + 1)/\(allowed) engine=\(engine): \(error.localizedDescription)"
                )
                try? await Task.sleep(nanoseconds: UInt64(delay(after: error) * 1_000_000_000))
                if Task.isCancelled { return .failure(CancellationError()) }
            }
        }
    }

    /// Vòng thử lại cho đường **gọi thẳng service** không qua coordinator (nghe thử giọng). Đường đọc truyện không
    /// dùng hàm này — coordinator tự lo (`run`).
    static func withRetry(
        maxAttempts: Int,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let attempts = max(1, maxAttempts)
        var attempt = 0
        while true {
            attempt += 1
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard attempt < attempts, !Task.isCancelled, isRetryable(error) else { throw error }
                try? await Task.sleep(nanoseconds: UInt64(delay(after: error) * 1_000_000_000))
                try Task.checkCancellation()
            }
        }
    }
}
