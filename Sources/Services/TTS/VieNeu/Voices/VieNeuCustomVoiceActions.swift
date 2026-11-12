import Foundation

/// Đổi tên / xoá **giọng nhân bản** (Nano hoặc Turbo) từ sheet chọn giọng (1.3.900) — thay màn "Giọng của tôi" cũ.
///
/// Ngoài việc ghi kho, phải giữ hai thứ khớp nhau:
/// - Engine Nano nạp catalog **một lần** (`VieNeuTTSEngine.prepareLocked`) ⇒ đổi kho giọng Nano phải `refreshVoiceCatalog`,
///   không thì giọng vừa đổi tên rơi im lặng về giọng mặc định (lỗi đã gặp ở màn cũ).
/// - Trình đọc đang dùng đúng giọng đó: Nano tra giọng **theo tên** ⇒ đổi tên thì chọn lại theo tên mới; xoá thì về giọng
///   mặc định của model.
@MainActor
enum VieNeuCustomVoiceActions {
    enum ActionError: LocalizedError {
        case storeUnavailable
        case notCustom

        var errorDescription: String? {
            switch self {
            case .storeUnavailable: return "Không dựng được thư mục VieNeu (Application Support không ghi được)."
            case .notCustom: return "Chỉ đổi tên / xoá được giọng nhân bản."
            }
        }
    }

    static func rename(_ entry: VieNeuVoiceEntry, to name: String) throws {
        guard entry.isMine else { throw ActionError.notCustom }
        let wasSelected = isReaderVoice(entry)
        switch entry.model {
        case .nano:
            guard let recordId = entry.nanoRecordId, let store = nanoStore() else { throw ActionError.storeUnavailable }
            try store.rename(id: recordId, to: name)
            refreshNanoCatalog()
            if wasSelected {
                TTSManager.shared.selectVieNeuVoice(VieNeuVoiceSelection(model: .nano, voiceId: name.trimmed))
            }
        case .turbo:
            try VieNeuTurboCustomVoiceRepository.shared.rename(id: entry.selection.voiceId, to: name)
        }
        VieNeuVoiceDirectory.shared.reload()
    }

    static func delete(_ entry: VieNeuVoiceEntry) throws {
        guard entry.isMine else { throw ActionError.notCustom }
        let wasSelected = isReaderVoice(entry)
        switch entry.model {
        case .nano:
            guard let recordId = entry.nanoRecordId, let store = nanoStore() else { throw ActionError.storeUnavailable }
            try store.delete(id: recordId)
            refreshNanoCatalog()
            if wasSelected {
                let fallback = VieNeuTTSService.shared?.defaultVoiceName ?? VieNeuBuiltinVoiceList.nanoDefaultName
                TTSManager.shared.selectVieNeuVoice(VieNeuVoiceSelection(model: .nano, voiceId: fallback))
            }
        case .turbo:
            try VieNeuTurboCustomVoiceRepository.shared.delete(id: entry.selection.voiceId)
            if wasSelected {
                // Rỗng ⇒ `TTSManager.effectiveVieNeuVoice` lấy giọng mặc định của manifest.
                TTSManager.shared.selectVieNeuVoice(VieNeuVoiceSelection(model: .turbo, voiceId: ""))
            }
        }
        VieNeuVoiceDirectory.shared.reload()
        AppLogger.shared.log("🎙️ [VieNeuVoices] Đã xoá giọng nhân bản \(entry.selection.key)")
    }

    /// Giọng trình đọc đang dùng (model hiệu lực + `selectedVoice`).
    static func isReaderVoice(_ entry: VieNeuVoiceEntry) -> Bool {
        let tts = TTSManager.shared
        return tts.tool == "vieneu"
            && VieNeuModelChoice.current == entry.model
            && tts.selectedVoice == entry.selection.voiceId
    }

    private static func nanoStore() -> VieNeuCustomVoiceStore? {
        (try? VieNeuModelStore()).map { VieNeuCustomVoiceStore(rootURL: $0.rootURL) }
    }

    private static func refreshNanoCatalog() {
        do {
            try VieNeuTTSService.shared?.refreshVoiceCatalog()
        } catch {
            AppLogger.shared.log("❌ [VieNeuVoices] Nạp lại danh sách giọng Nano lỗi: \(error.localizedDescription)")
        }
    }
}
