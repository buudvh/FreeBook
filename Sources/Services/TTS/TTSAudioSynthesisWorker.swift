import Foundation
import os

/// Worker 2 chuyên trách tổng hợp âm thanh TTS (Audio Synthesis Worker)
/// Facade stateless quản lý pacing + coordinator synthesis. Callers own Tasks.
internal actor TTSAudioSynthesisWorker {
    internal init() {}

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
        do {
            let data = try await RemoteTTSSynthesisCoordinator.shared.synthesize(
                key: synthesisKey,
                engine: engine,
                textLength: textLength,
                priority: priority
            ) {
                operationStartedAt.withLock { $0 = ProcessInfo.processInfo.systemUptime }
                return try await operation()
            }
            Self.logSlowWait(priority: priority, engine: engine, enqueuedAt: enqueuedAt,
                             operationStartedAt: operationStartedAt.withLock { $0 }, outcome: "ok")
            return data
        } catch {
            if !(error is CancellationError) {
                Self.logSlowWait(priority: priority, engine: engine, enqueuedAt: enqueuedAt,
                                 operationStartedAt: operationStartedAt.withLock { $0 }, outcome: "error")
            }
            throw error
        }
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
