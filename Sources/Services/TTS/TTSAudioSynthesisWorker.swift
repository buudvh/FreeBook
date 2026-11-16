import Foundation
import os

/// Worker 2 chuyên trách tổng hợp âm thanh TTS (Audio Synthesis Worker)
/// Facade stateless quản lý pacing + coordinator synthesis. Callers own Tasks.
internal actor TTSAudioSynthesisWorker {
    internal init() {}

    /// Chính sách của một lượt tổng hợp (1.3.953): số lượt thử + timeout mỗi lượt.
    private struct Policy {
        let attempts: Int
        let timeoutSeconds: TimeInterval
    }

    /// Tổng hợp âm thanh cho một đoạn văn với khoảng dãn nạp bậc thang
    internal func synthesizeParagraph(
        synthesisKey: String,
        engine: String,
        textLength: Int,
        priority: RemoteTTSSynthesisCoordinator.Priority,
        offset: Int,
        prefetchDelayMs: Int,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if offset >= 1 {
            let delayStepMs = max(300, prefetchDelayMs)
            try await Task.sleep(nanoseconds: UInt64(offset * delayStepMs) * 1_000_000)
        }

        let enqueuedAt = ProcessInfo.processInfo.systemUptime
        let operationStartedAt = OSAllocatedUnfairLock<TimeInterval?>(initialState: nil)
        let policy = Self.policy(priority: priority)
        do {
            let data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                key: synthesisKey,
                engine: engine,
                textLength: textLength,
                priority: priority
            ) {
                operationStartedAt.withLock { $0 = ProcessInfo.processInfo.systemUptime }
                // Timeout bọc **trong** mỗi lượt thử, retry bọc **ngoài** ⇒ mỗi lượt thử có timeout riêng.
                // Retry nằm trong closure ⇒ đoạn đang đọc giữ slot coordinator liền mạch: nếu retry nằm ngoài
                // coordinator thì lúc một lượt thử hụt, `RemoteTTSSynthesisCoordinator.complete()` gọi
                // `startNextIfNeeded()` ngay ⇒ lượt nạp trước chiếm slot trước khi lượt retry kịp xếp lại.
                return try await Self.withRetry(maxAttempts: policy.attempts) {
                    try await Self.withTimeout(seconds: policy.timeoutSeconds, operation: operation)
                }
            }
            Self.logSlowWait(priority: priority, engine: engine, enqueuedAt: enqueuedAt,
                             operationStartedAt: operationStartedAt.withLock { $0 }, outcome: "ok")
            return data
        } catch {
            if !(error is CancellationError) {
                Self.logSlowWait(priority: priority, engine: engine, enqueuedAt: enqueuedAt,
                                 operationStartedAt: operationStartedAt.withLock { $0 }, outcome: "error")
                // Lượt **nạp trước** hụt timeout ⇒ tín hiệu server chết chung ⇒ bật giọng dự phòng ngay (1.3.953).
                // Đoạn đang đọc thì để `switchToOnlineFallback` lo (đã có sẵn ở `playGoogleTTS`/`playExtensionTTS`).
                if priority == .prefetch {
                    await TTSManager.shared.handleOnlinePrefetchFailure(error)
                }
            }
            throw error
        }
    }

    /// Chạy `operation` với giới hạn thời gian (1.3.953). Hết giờ ⇒ huỷ Task con (huỷ luôn request mạng /
    /// lệnh JS đang chờ) rồi ném `TTSSynthesisTimeoutError`.
    internal static func withTimeout(
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

    /// Thử lại khi lỗi — **mọi lỗi** trừ `CancellationError` (1.3.953). Giữa các lượt nghỉ 400 ms.
    internal static func withRetry(
        maxAttempts: Int,
        operation: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        let attempts = max(1, maxAttempts)
        var lastError: Error?
        for attempt in 1...attempts {
            do {
                return try await operation()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                guard attempt < attempts else { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
                try Task.checkCancellation()
            }
        }
        throw lastError ?? TTSSynthesisTimeoutError.timedOut(seconds: 0)
    }

    /// Chính sách theo loại lượt (1.3.953): đoạn đang đọc thử lại theo cấu hình; lượt nạp trước thử **một** lần
    /// (server chết thì thử lại cũng vô ích mà lại tốn slot hàng đợi).
    private static func policy(priority: RemoteTTSSynthesisCoordinator.Priority) -> Policy {
        let retries = priority == .current ? TTSOnlineSynthesisSettings.effectiveRetryCount : 0
        return Policy(
            attempts: 1 + max(0, retries),
            timeoutSeconds: TimeInterval(TTSOnlineSynthesisSettings.effectiveTimeoutSeconds)
        )
    }

    /// `[TTSPerf] RemoteWait` (1.3.671) — chỉ khi đoạn đang đọc phải chờ ≥ 400 ms hoặc một lượt tổng hợp chạy ≥ 2 s.
    /// `queueMs` = chờ tới lượt trong `RemoteTTSSynthesisCoordinator` (gồm chờ thread của cooperative pool), `runMs` =
    /// mạng + nhận kết quả (cũng cần thread của pool); `-1` = gộp vào job cùng khoá đang chạy. `jsInFlight` = số lời gọi
    /// JS đồng bộ đang chặn pool lúc ghi — cao gần `cores` mà `queueMs`/`runMs` lớn ⇒ TTS đói thread, không phải mạng chậm.
    private static func logSlowWait(
        priority: RemoteTTSSynthesisCoordinator.Priority,
        engine: String,
        enqueuedAt: TimeInterval,
        operationStartedAt: TimeInterval?,
        outcome: String
    ) {
        guard AppLogger.shared.isLoggingEnabled else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let waitMs = (now - enqueuedAt) * 1000
        let queueMs = operationStartedAt.map { ($0 - enqueuedAt) * 1000 } ?? -1
        let runMs = operationStartedAt.map { (now - $0) * 1000 } ?? -1
        guard (priority == .current && waitMs >= 400) || runMs >= 2000 else { return }
        AppLogger.shared.log(String(
            format: "[TTSPerf] RemoteWait priority=%@ engine=%@ waitMs=%.0f queueMs=%.0f runMs=%.0f outcome=%@ jsInFlight=%d cores=%d",
            String(describing: priority), engine, waitMs, queueMs, runMs, outcome,
            JSExecutionTelemetry.inFlightCount, ProcessInfo.processInfo.activeProcessorCount
        ))
    }

    /// Hủy các tác vụ nạp trước (prefetch), giữ nguyên tác vụ đang đọc đoạn hiện tại (.current)
    internal func cancelPrefetchTasks() async {
        await RemoteTTSSynthesisCoordinator.shared.cancelPrefetchOnly()
    }

    /// Hủy toàn bộ tác vụ tổng hợp âm thanh đang chờ
    internal func cancelAll() async {
        await RemoteTTSSynthesisCoordinator.shared.cancelAll()
    }
}
