import Foundation

/// Worker 2 chuyên trách tổng hợp âm thanh TTS (Audio Synthesis Worker)
/// Quản lý việc nạp đệm âm thanh MP3/PCM vào RAM đệm cho Google TTS, Ext TTS và NghiTTS.
public actor TTSAudioSynthesisWorker {
    private var inFlightTasks: [Int: Task<Data?, Error>] = [:]

    public init() {}

    /// Tổng hợp âm thanh cho một đoạn văn với khoảng dãn nạp bậc thang
    public func synthesizeParagraph(
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

        return try await RemoteTTSSynthesisCoordinator.shared.synthesize(
            key: synthesisKey,
            engine: engine,
            textLength: textLength,
            priority: priority,
            operation: operation
        )
    }

    /// Hủy toàn bộ tác vụ tổng hợp âm thanh đang chờ
    public func cancelAll() {
        for task in inFlightTasks.values {
            task.cancel()
        }
        inFlightTasks.removeAll()
        Task {
            await RemoteTTSSynthesisCoordinator.shared.cancelAll()
        }
    }
}
