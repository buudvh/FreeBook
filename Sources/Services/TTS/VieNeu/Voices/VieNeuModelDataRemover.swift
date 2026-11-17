import Foundation

/// Xoá dữ liệu VieNeu tải về: "Xoá tất cả dữ liệu Nano / Turbo" (nút ở cuối mục Nano / Turbo của trang Cài đặt VieNeu TTS)
/// và "Xoá giọng" một giọng Turbo tải về (nút 🗑 cuối hàng ở sheet chọn giọng). Giọng nhân bản (`CustomVoices/`) **không**
/// bị đụng. Mọi lối đều từ chối khi đang có lượt tải VieNeu.
///
/// - Nano: 8 file lõi + gói nhân bản Nano (`VieNeuModelStore.deleteAll` tự giữ `sea_g2p.bin` / gói nhân bản Turbo khi máy
///   còn Turbo) + gói và bản biên dịch **Tăng tốc Core ML** (`VieNeuCoreMLAccelerator.deleteData`).
/// - Turbo: GGUF + manifest + mọi giọng tải về (`VieNeuTurboModelStore.deleteAll`).
/// - Một giọng Turbo: chỉ `Voices/<id>/` (`VieNeuTurboModelStore.deleteDownloadedVoice`, vài KB); model giữ lại. Trình đọc
///   chọn giọng đó mà chưa đọc thì không cần làm gì: đoạn đầu tiên tự tải lại file giọng (`VieNeuTurboTTSService.ensureVoice`).
/// - Trình đọc đang đọc bằng đúng model (hoặc đúng giọng) đó ⇒ dừng trước khi nhả engine và xoá, kẻo đoạn kế nạp lại đúng
///   file vừa xoá.
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
        // Nhả ngoài main (1.3.972): `releaseEngineRuntime()` chờ khoá engine, mà một lượt Nano đang tổng hợp giữ khoá vài
        // giây và `stop()` không cắt được nó giữa chừng — gọi thẳng ở đây là đứng UI.
        await VieNeuTurboTTSService.releaseNanoEngineIfLoaded(reason: "trước khi xoá dữ liệu Nano")
        // Vừa nhường main trong lúc chờ khoá ⇒ kiểm lại: một lượt tải có thể đã bắt đầu.
        guard !ModelDownloadCenter.shared.isVieNeuBusy else { throw RemovalError.downloading }
        try await Task.detached(priority: .userInitiated) {
            try VieNeuModelStore().deleteAll()
        }.value
        accelerator.deleteData()
        VieNeuVoiceDirectory.shared.refreshAvailability()
        AppLogger.shared.log("🗑️ [VieNeu] Đã xoá dữ liệu Nano (model + gói nhân bản + Tăng tốc Core ML)")
    }

    static func deleteTurbo() async throws {
        guard !ModelDownloadCenter.shared.isVieNeuBusy else { throw RemovalError.downloading }
        let modelBefore = VieNeuModelChoice.current
        stopReaderIfUsing(.turbo)
        await VieNeuTurboRuntime.shared.release()
        try await Task.detached(priority: .userInitiated) {
            try VieNeuTurboModelStore().deleteAll()
        }.value
        // Một lượt Turbo lọt vào giữa lúc nhả và lúc xoá có thể đã nạp lại model ⇒ nhả lần nữa, kèm bộ phiên âm của Turbo
        // (file đã xoá, không ai còn nhả hộ).
        await VieNeuTurboTTSService.releaseForNano()
        VieNeuVoiceDirectory.shared.refreshAvailability()
        // Đang chọn giọng Turbo ⇒ model hiệu lực vừa lùi về Nano mà `selectedVoice` còn là id giọng Turbo (1.3.972).
        TTSManager.shared.reapplyVieNeuReaderIfModelChanged(from: modelBefore, reason: "xoa du lieu Turbo")
        AppLogger.shared.log("🗑️ [VieNeuTurbo] Đã xoá dữ liệu Turbo (model + giọng tải về)")
    }

    /// Xoá file của **một** giọng Turbo tải về (`voiceId` trần như `TTSManager.selectedVoice`, không phải khoá
    /// `turbo:<id>`). Id giọng tự tạo bị bỏ qua ở tầng kho — `CustomVoices/` không bao giờ bị đụng.
    static func deleteTurboVoice(voiceId: String) async throws {
        guard !ModelDownloadCenter.shared.isVieNeuBusy else { throw RemovalError.downloading }
        stopReaderIfUsing(.turbo, voiceId: voiceId)
        try await Task.detached(priority: .userInitiated) {
            try VieNeuTurboModelStore().deleteDownloadedVoice(voiceId: voiceId)
        }.value
        VieNeuVoiceDirectory.shared.refreshAvailability()
        AppLogger.shared.log("🗑️ [VieNeuTurbo] Đã xoá file giọng \(voiceId)")
    }

    /// Dừng trình đọc khi nó đang dùng dữ liệu sắp xoá: model hiệu lực là `model`, hoặc đang **đọc lai** — khi đó model
    /// kia cũng được dùng theo từng đoạn, `VieNeuModelChoice.current` chỉ là model chính (1.3.972). `voiceId` khác `nil`
    /// ⇒ chỉ dừng khi trình đọc đang dùng đúng giọng Turbo đó (giọng đang chọn, hoặc giọng Turbo của cặp đọc lai).
    private static func stopReaderIfUsing(_ model: VieNeuModelChoice, voiceId: String? = nil) {
        let tts = TTSManager.shared
        guard tts.tool == "vieneu", tts.isPlaying || tts.showFloatingWidget else { return }
        let usesModel = VieNeuModelChoice.current == model
        let hybrid = VieNeuHybridRouting.context(voice: tts.selectedVoice)
        if let voiceId {
            guard (usesModel && tts.selectedVoice == voiceId) || hybrid?.pair.turboVoiceId == voiceId else { return }
        } else {
            guard usesModel || hybrid != nil else { return }
        }
        let target = voiceId.map { "giọng \($0)" } ?? "dữ liệu \(model.label)"
        AppLogger.shared.log("⏹️ [VieNeu] Dừng TTS trước khi xoá \(target) (trình đọc đang dùng)")
        tts.stop()
    }
}
