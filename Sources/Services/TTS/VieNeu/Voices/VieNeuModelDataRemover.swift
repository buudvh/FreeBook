import Foundation

/// "Xoá dữ liệu Nano / Turbo" — nhấn giữ một giọng có sẵn ở sheet chọn giọng (1.3.919; màn thử và nút Xoá ở Cài đặt VieNeu
/// đã bỏ, đây là lối duy nhất lấy lại dung lượng model). Giọng nhân bản (`CustomVoices/`) **không** bị đụng.
///
/// - Nano: 8 file lõi + gói nhân bản Nano (`VieNeuModelStore.deleteAll` tự giữ `sea_g2p.bin` / gói nhân bản Turbo khi máy
///   còn Turbo) + gói và bản biên dịch **Tăng tốc Core ML** (`VieNeuCoreMLAccelerator.deleteData`).
/// - Turbo: GGUF + manifest + mọi giọng tải về (`VieNeuTurboModelStore.deleteAll`).
/// - Trình đọc đang đọc bằng đúng model đó ⇒ dừng trước khi nhả engine và xoá, kẻo đoạn kế nạp lại đúng file vừa xoá.
@MainActor
enum VieNeuModelDataRemover {
    enum RemovalError: LocalizedError {
        case downloading
        case preparingCoreML

        var errorDescription: String? {
            switch self {
            case .downloading: return "Đang tải dữ liệu VieNeu — đợi tải xong rồi xoá."
            case .preparingCoreML: return "Đang chuẩn bị Tăng tốc Core ML — đợi xong rồi xoá."
            }
        }
    }

    static func deleteNano() async throws {
        guard !ModelDownloadCenter.shared.isVieNeuBusy else { throw RemovalError.downloading }
        let accelerator = VieNeuCoreMLAccelerator.shared
        guard !accelerator.isBusy else { throw RemovalError.preparingCoreML }
        stopReaderIfUsing(.nano)
        _ = VieNeuTTSService.shared?.releaseEngineRuntime()
        try await Task.detached(priority: .userInitiated) {
            try VieNeuModelStore().deleteAll()
        }.value
        accelerator.deleteData()
        VieNeuVoiceDirectory.shared.refreshAvailability()
        AppLogger.shared.log("🗑️ [VieNeu] Đã xoá dữ liệu Nano (model + gói nhân bản + Tăng tốc Core ML)")
    }

    static func deleteTurbo() async throws {
        guard !ModelDownloadCenter.shared.isVieNeuBusy else { throw RemovalError.downloading }
        stopReaderIfUsing(.turbo)
        await VieNeuTurboRuntime.shared.release()
        try await Task.detached(priority: .userInitiated) {
            try VieNeuTurboModelStore().deleteAll()
        }.value
        VieNeuVoiceDirectory.shared.refreshAvailability()
        AppLogger.shared.log("🗑️ [VieNeuTurbo] Đã xoá dữ liệu Turbo (model + giọng tải về)")
    }

    private static func stopReaderIfUsing(_ model: VieNeuModelChoice) {
        let tts = TTSManager.shared
        guard tts.tool == "vieneu", VieNeuModelChoice.current == model, tts.isPlaying || tts.showFloatingWidget else { return }
        AppLogger.shared.log("⏹️ [VieNeu] Dừng TTS trước khi xoá dữ liệu \(model.label) (trình đọc đang dùng)")
        tts.stop()
    }
}
