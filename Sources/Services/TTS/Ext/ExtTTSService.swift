import Foundation

/// Tổng hợp audio bằng extension JavaScript (`tts.js`). Chỉ trả **dữ liệu đã mã hoá** (mp3/wav) —
/// việc giải mã và phát thuộc `TTSManager`.
///
/// 1.3.330 xoá đường PCM cũ (`synthesize(...targetFormat:)`, `preprocessBufferForExtTTS`, bộ theo dõi
/// file tạm): không caller nào trong `Sources/` dùng nó từ lâu, và nó còn áp chuẩn hoá biên độ + fade
/// **hai lần** lên cùng một buffer. Cần lại đường PCM thì viết mới, đừng phục hồi bản cũ.
public final class ExtTTSService: Sendable {
    public init() {}

    /// Thử lại + timeout do `RemoteTTSSynthesisCoordinator` lo (`RemoteTTSAttemptPolicy`, 1.3.960) — ở đây chỉ gọi thẳng
    /// runtime rồi giải mã base64. Số lần thử lại theo cấu hình chung (`TTSOnlineSynthesisSettings`).
    public func synthesizeData(
        text: String,
        voice: String,
        localPath: String,
        configJson: String
    ) async throws -> Data {
        // "Phiên âm tiếng Nhật" lưu riêng từng tiện ích theo `packageId` (1.3.973). Không tra được `packageId` (bản nháp
        // debug ngoài `extensions/`) ⇒ không có cài đặt ⇒ giữ nguyên chữ.
        let spokenText = ExtensionLibraryRepository.packageId(forLocalPath: localPath)
            .map { TTSJapaneseTextTransliterator.apply(text, tool: $0) } ?? text
        let base64String = try await ExtensionManager.shared.ttsGenerate(
            localPath: localPath,
            text: spokenText,
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
