import Foundation

/// Bước **tạo giọng Nano** từ một file mẫu — dùng chung cho sheet nhân bản (`VieNeuVoiceCloneFlow+Save`) và "Tạo bản Nano"
/// (`VieNeuVoiceCopyRunner`, 1.3.937). Đường Nano giữ nguyên như 1.3.901: `enrollVoice` (ngữ cảnh ORT riêng, không khử
/// nhiễu) → lưu vào kho Nano (chép mẫu) → nạp lại catalog của engine (engine nạp catalog một lần ⇒ thiếu bước này giọng
/// mới rơi về giọng mặc định).
@MainActor
enum VieNeuNanoVoiceCreator {
    enum CreateError: LocalizedError {
        case engineUnavailable

        var errorDescription: String? { "Không dựng được engine VieNeu." }
    }

    /// `sourceTurboVoiceId` = giọng Turbo mà bản Nano này nhân bản từ đó (cặp của đọc lai); `nil` ở sheet nhân bản.
    @discardableResult
    static func create(
        name: String,
        sampleURL: URL,
        sourceTurboVoiceId: String? = nil,
        onStage: (@Sendable (VieNeuVoiceCloner.Stage) -> Void)? = nil
    ) async throws -> VieNeuCustomVoiceStore.Record {
        guard let service = VieNeuTTSService.shared else { throw CreateError.engineUnavailable }
        let enrollment = try await service.enrollVoice(sampleURL: sampleURL, onStage: onStage)
        let record = try service.customVoiceStore.add(
            name: name,
            speakerEmbedding: enrollment.speakerEmbedding,
            style: enrollment.style,
            sampleSourceURL: sampleURL,
            sourceTurboVoiceId: sourceTurboVoiceId
        )
        do {
            try service.refreshVoiceCatalog()
        } catch {
            AppLogger.shared.log("❌ [VieNeuClone] Nạp lại danh sách giọng Nano lỗi: \(error.localizedDescription)")
        }
        return record
    }
}
