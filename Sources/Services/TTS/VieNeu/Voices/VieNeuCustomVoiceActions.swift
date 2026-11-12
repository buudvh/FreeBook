import Foundation

/// Đổi tên / xoá **giọng nhân bản** (Nano hoặc Turbo) từ sheet chọn giọng (1.3.900) — thay màn "Giọng của tôi" cũ.
///
/// Ngoài việc ghi kho, phải giữ hai thứ khớp nhau:
/// - Engine Nano nạp catalog **một lần** (`VieNeuTTSEngine.prepareLocked`) ⇒ đổi kho giọng Nano phải `refreshVoiceCatalog`,
///   không thì giọng vừa đổi tên rơi im lặng về giọng mặc định (lỗi đã gặp ở màn cũ).
/// - Trình đọc / lựa chọn đã lưu / "giọng Nano dùng gần nhất" đang trỏ đúng giọng đó: Nano tra giọng **theo tên** ⇒ đổi tên
///   thì trỏ sang tên mới, xoá thì về giọng mặc định của model — nhưng không bao giờ ghi đè lựa chọn Turbo đang lùi về
///   Nano (`retargetNanoVoice`).
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
        switch entry.model {
        case .nano:
            guard let recordId = entry.nanoRecordId, let store = nanoStore() else { throw ActionError.storeUnavailable }
            try store.rename(id: recordId, to: name)
            refreshNanoCatalog()
            retargetNanoVoice(from: entry.selection.voiceId, to: name.trimmed)
        case .turbo:
            // Giọng Turbo tra theo id (`custom_…`) ⇒ đổi tên không đụng lựa chọn.
            try VieNeuTurboCustomVoiceRepository.shared.rename(id: entry.selection.voiceId, to: name)
        }
        VieNeuVoiceDirectory.shared.reload()
    }

    static func delete(_ entry: VieNeuVoiceEntry) throws {
        guard entry.isMine else { throw ActionError.notCustom }
        switch entry.model {
        case .nano:
            guard let recordId = entry.nanoRecordId, let store = nanoStore() else { throw ActionError.storeUnavailable }
            try store.delete(id: recordId)
            refreshNanoCatalog()
            let fallback = VieNeuTTSService.shared?.defaultVoiceName ?? VieNeuBuiltinVoiceList.nanoDefaultName
            retargetNanoVoice(from: entry.selection.voiceId, to: fallback)
        case .turbo:
            let id = entry.selection.voiceId
            try VieNeuTurboCustomVoiceRepository.shared.delete(id: id)
            let stored = VieNeuVoiceSelection.stored
            if stored.model == .turbo, stored.voiceId == id {
                // Rỗng ⇒ `TTSManager.effectiveVieNeuVoice` lấy giọng mặc định của manifest.
                let fallback = VieNeuVoiceSelection(model: .turbo, voiceId: "")
                if TTSManager.shared.tool == "vieneu" {
                    TTSManager.shared.selectVieNeuVoice(fallback)
                } else {
                    VieNeuVoiceSelection.store(fallback)
                }
            }
        }
        VieNeuVoiceDirectory.shared.reload()
        AppLogger.shared.log("🎙️ [VieNeuVoices] Đã xoá giọng nhân bản \(entry.selection.key)")
    }

    /// Giọng Nano tên `oldName` vừa đổi tên / bị xoá ⇒ mọi chỗ còn trỏ tên cũ chuyển sang `newName` (engine Nano tra giọng
    /// theo **tên**):
    /// - lựa chọn đã lưu là giọng Nano đó ⇒ chọn lại (trình đọc đang là VieNeu thì qua `selectVieNeuVoice`, không thì chỉ
    ///   ghi lựa chọn);
    /// - lựa chọn đã lưu là **Turbo** mà trình đọc đang lùi về Nano bằng giọng đó ⇒ **không** chọn lại (sẽ ghi đè mất lựa
    ///   chọn Turbo), chỉ đổi giọng đang đọc — `persistVoice` khi đó chỉ ghi "giọng Nano dùng gần nhất";
    /// - "giọng Nano dùng gần nhất" là giọng đó ⇒ cập nhật.
    private static func retargetNanoVoice(from oldName: String, to newName: String) {
        guard !oldName.isEmpty, oldName != newName else { return }
        if VieNeuVoiceSelection.lastNanoVoice == oldName {
            UserDefaults.standard.set(newName, forKey: VieNeuVoiceSelection.lastNanoVoiceKey)
        }
        let tts = TTSManager.shared
        let stored = VieNeuVoiceSelection.stored
        if stored.model == .nano, stored.voiceId == oldName {
            let replacement = VieNeuVoiceSelection(model: .nano, voiceId: newName)
            if tts.tool == "vieneu" {
                tts.selectVieNeuVoice(replacement)
            } else {
                VieNeuVoiceSelection.store(replacement)
            }
        } else if tts.tool == "vieneu", VieNeuModelChoice.current == .nano, tts.selectedVoice == oldName {
            tts.selectedVoice = newName
        }
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
