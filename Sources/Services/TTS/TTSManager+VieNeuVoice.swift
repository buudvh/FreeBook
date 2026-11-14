import Foundation

/// Chọn giọng VieNeu — **model đi theo giọng** (1.3.898, `VieNeuVoiceSelection`). Tách khỏi `TTSManager+VieNeu.swift`
/// cho file đó khỏi phình; `TTSManager.swift` là file legacy chỉ được giảm dòng.
extension TTSManager {
    /// Giọng trình đọc dùng cho **model hiệu lực** (`VieNeuModelChoice.current`):
    /// - Turbo ⇒ id đã lưu qua `resolveVoiceId` (giọng không còn trong manifest / giọng tự tạo đã xoá ⇒ giọng mặc định).
    /// - Nano ⇒ giọng Nano đã lưu; đang lùi về Nano (lựa chọn là Turbo mà Turbo thiếu file) ⇒ giọng Nano dùng gần nhất;
    ///   không có ⇒ giọng mặc định của catalog.
    static func effectiveVieNeuVoice() -> String {
        let selection = VieNeuVoiceSelection.stored
        switch VieNeuModelChoice.current {
        case .turbo:
            let requested = selection.model == .turbo ? selection.voiceId : ""
            guard let turbo = VieNeuTurboTTSService.shared else {
                return requested.isEmpty ? VieNeuTurboModelStore.fallbackVoiceId : requested
            }
            return turbo.resolveVoiceId(requested.isEmpty ? turbo.defaultVoiceId : requested)
        case .nano:
            if selection.model == .nano, !selection.voiceId.isEmpty { return selection.voiceId }
            if let last = VieNeuVoiceSelection.lastNanoVoice { return last }
            return VieNeuTTSService.shared?.defaultVoiceName ?? ""
        }
    }

    /// Chọn một giọng VieNeu (sheet "Giọng đọc", sheet nhân bản giọng).
    ///
    /// - **Cùng model** với trình đọc đang chạy ⇒ chỉ đổi `selectedVoice` (`didSet` lưu + bỏ phần đệm).
    /// - **Khác model** (hoặc trình đọc chưa là VieNeu) ⇒ ghi lựa chọn **trước** rồi gán `tool = "vieneu"`: `tool.didSet`
    ///   nạp lại tham số (giọng theo model mới), bỏ phần đệm và `scheduleNghiWarmUp` nạp sẵn đúng engine — engine kia
    ///   bị nhả trong `prepare` của engine mới. Swift chạy `didSet` cả khi giá trị không đổi.
    ///
    /// Cả hai đường đổi `selectedVoice` (khác id) ⇒ `TTSSettingsSnapshot` khác ⇒ đóng Cài đặt TTS thì
    /// `resumeAfterSettings` dựng lại đoạn bằng giọng mới.
    func selectVieNeuVoice(_ selection: VieNeuVoiceSelection) {
        let wasVieNeu = tool == "vieneu"
        let previousModel = VieNeuModelChoice.current
        VieNeuVoiceSelection.store(selection)
        let newModel = VieNeuModelChoice.current
        AppLogger.shared.log("[TTSRoute] chon giong VieNeu \(selection.storageValue) model=\(previousModel.rawValue)->\(newModel.rawValue)")
        if wasVieNeu && previousModel == newModel {
            let voice = Self.effectiveVieNeuVoice()
            if selectedVoice != voice {
                selectedVoice = voice
                // Đọc lai Nano · Turbo (1.3.934): giọng mới có / mất cặp ⇒ engine đổi (bọc ↔ thường); chuẩn bị lại để model
                // phụ đã nạp lười được nhả và mức âm lượng nhớ của giọng cũ được quên.
                scheduleNghiWarmUp()
            }
            if newModel == .turbo { VieNeuTurboTTSService.shared?.prefetchVoice(voice) }
        } else {
            tool = "vieneu"
        }
    }
}
