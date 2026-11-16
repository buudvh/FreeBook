import Foundation

/// Tổng hợp audio bằng extension JavaScript (`tts.js`). Chỉ trả **dữ liệu đã mã hoá** (mp3/wav) —
/// việc giải mã và phát thuộc `TTSManager`.
///
/// 1.3.330 xoá đường PCM cũ (`synthesize(...targetFormat:)`, `preprocessBufferForExtTTS`, bộ theo dõi
/// file tạm): không caller nào trong `Sources/` dùng nó từ lâu, và nó còn áp chuẩn hoá biên độ + fade
/// **hai lần** lên cùng một buffer. Cần lại đường PCM thì viết mới, đừng phục hồi bản cũ.
public final class ExtTTSService: Sendable {
    public init() {}

    /// Retry do tầng chung lo (`TTSAudioSynthesisWorker.withRetry`, 1.3.953) — ở đây chỉ gọi thẳng runtime
    /// rồi giải mã base64. Số lần thử lại lấy từ cấu hình chung (mặc định 3; có giọng dự phòng thì 0).
    public func synthesizeData(
        text: String,
        voice: String,
        localPath: String,
        configJson: String
    ) async throws -> Data {
        let base64String = try await ExtensionManager.shared.ttsGenerate(
            localPath: localPath,
            text: text,
            voice: voice,
            configJson: configJson
        )

        try Task.checkCancellation()
        guard let audioData = Data(base64Encoded: base64String.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NSError(domain: "ExtTTSService", code: -20, userInfo: [NSLocalizedDescriptionKey: "Dữ liệu âm thanh Base64 không hợp lệ"])
        }
        return audioData
    }

    public func resetRuntime() async {
        await ExtensionManager.shared.resetTTSRuntime()
    }
}
