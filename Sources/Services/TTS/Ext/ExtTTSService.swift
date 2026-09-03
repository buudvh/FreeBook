import Foundation

/// Tổng hợp audio bằng extension JavaScript (`tts.js`). Chỉ trả **dữ liệu đã mã hoá** (mp3/wav) —
/// việc giải mã và phát thuộc `TTSManager`.
///
/// 1.3.330 xoá đường PCM cũ (`synthesize(...targetFormat:)`, `preprocessBufferForExtTTS`, bộ theo dõi
/// file tạm): không caller nào trong `Sources/` dùng nó từ lâu, và nó còn áp chuẩn hoá biên độ + fade
/// **hai lần** lên cùng một buffer. Cần lại đường PCM thì viết mới, đừng phục hồi bản cũ.
public final class ExtTTSService: Sendable {
    public init() {}

    /// Retry sở hữu tại đây, **một tầng duy nhất** cho toàn pipeline: `TTSManager` không được bọc
    /// thêm vòng retry quanh hàm này.
    public func synthesizeData(
        text: String,
        voice: String,
        localPath: String,
        configJson: String
    ) async throws -> Data {
        let maxAttempts = 2
        var attempt = 0

        while true {
            attempt += 1
            do {
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
            } catch {
                if Task.isCancelled || attempt >= maxAttempts || !isTransient(error) {
                    throw error
                }
                AppLogger.shared.log("⚠️ [ExtTTSService] Thử lại lượt \(attempt)/\(maxAttempts) do lỗi tạm thời: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }

    public func resetRuntime() async {
        await ExtensionManager.shared.resetTTSRuntime()
    }

    private func isTransient(_ error: Error) -> Bool {
        let nsError = error as NSError
        let message = error.localizedDescription.lowercased()
        return nsError.domain == NSURLErrorDomain ||
            nsError.code == 408 ||
            nsError.code == 429 ||
            (500...599).contains(nsError.code) ||
            message.contains("timed out") ||
            message.contains("timeout") ||
            message.contains("temporarily") ||
            message.contains("service unavailable") ||
            message.contains("network")
    }
}
