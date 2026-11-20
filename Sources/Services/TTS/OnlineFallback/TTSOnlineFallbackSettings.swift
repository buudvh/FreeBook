import Foundation

/// **Giọng dự phòng** khi TTS online (Google Cloud TTS / tiện ích TTS) lỗi (1.3.945, anh Bửu duyệt mockup): một trình đọc
/// offline — NghiTTS (Piper), VieNeu hoặc vtts (2026-11-20) — chọn ở màn "Giọng dự phòng" (Cài đặt TTS › Khi giọng online lỗi).
///
/// Chỉ lưu **trình đọc nào** (`toolKey`, rỗng / thiếu = Không dùng). Giọng, tốc độ, tốc độ tổng hợp, từ điển phiên âm… là
/// cài đặt **của chính engine đó** (`nghittsVoice` / `VieNeuVoiceSelection` / `vttsVoice`, `nghittsRate` / `vieneuRate` /
/// `vttsRate`…) — chung với lúc engine đó là trình đọc chính, nên màn "Giọng dự phòng" dựng y các mục của Cài đặt TTS khi
/// chọn engine đó. `rawValue` = `TTSManager.tool` của engine.
enum TTSOnlineFallbackSettings {
    enum Engine: String, CaseIterable, Identifiable, Sendable {
        case nghitts
        case vieneu
        case vtts

        var id: String { rawValue }
        var title: String {
            switch self {
            case .nghitts: return "NghiTTS"
            case .vieneu: return "VieNeu"
            case .vtts: return "vtts"
            }
        }
        /// Chữ của Picker — trùng Picker "Trình đọc" của Cài đặt TTS.
        var pickerTitle: String {
            switch self {
            case .nghitts: return "NghiTTS (Piper Offline)"
            case .vieneu: return "VieNeu-TTS v3 (Offline)"
            case .vtts: return "vtts Việt–Anh (Offline)"
            }
        }
    }

    static let toolKey = "ttsOnlineFallbackTool"

    static var engine: Engine? {
        get { UserDefaults.standard.string(forKey: toolKey).flatMap(Engine.init(rawValue:)) }
        set { UserDefaults.standard.set(newValue?.rawValue ?? "", forKey: toolKey) }
    }

    /// Trình đọc chính đi qua mạng (Google / tiện ích) — chỉ khi đó mới có giọng dự phòng.
    static func isOnlineTool(_ tool: String) -> Bool {
        tool == "google" || TTSManager.isExtensionTool(tool)
    }

    /// Khoá tốc độ phát của engine — đúng khoá `TTSManager.loadParamsForCurrentTool` đọc khi engine đó là trình đọc chính.
    static func speedKey(for engine: Engine) -> String {
        switch engine {
        case .nghitts: return "nghittsRate"
        case .vieneu: return TTSManager.VieNeuSettingsKey.rate
        case .vtts: return TTSManager.VttsSettings.rateKey
        }
    }

    /// Tốc độ phát của engine dự phòng; chưa lưu ⇒ `ttsRate` ⇒ 1,0 (như lúc nạp tham số của engine).
    static func playbackSpeed(for engine: Engine) -> Double {
        let defaults = UserDefaults.standard
        let saved = defaults.double(forKey: speedKey(for: engine))
        if saved > 0 { return saved }
        let global = defaults.double(forKey: "ttsRate")
        return global > 0 ? global : 1.0
    }

    static func setPlaybackSpeed(_ value: Double, for engine: Engine) {
        UserDefaults.standard.set((value * 10).rounded() / 10, forKey: speedKey(for: engine))
    }

    /// Giọng NghiTTS đã lưu (chung với lúc NghiTTS là trình đọc chính).
    static var nghiVoice: String {
        UserDefaults.standard.string(forKey: NghiVoiceDirectory.voiceDefaultsKey) ?? NghiTTSClient.defaultVietnameseVoice.name
    }

    /// Phần cài đặt dự phòng đưa vào `TTSSettingsSnapshot`: đổi ⇒ đóng Cài đặt TTS là dựng lại đoạn, bỏ tiếng dự phòng đã
    /// nạp trước theo cài đặt cũ. Trình đọc chính không online hoặc không dùng dự phòng ⇒ rỗng.
    static func fingerprint(mainTool: String) -> String {
        guard isOnlineTool(mainTool), let engine else { return "" }
        let defaults = UserDefaults.standard
        let speed = playbackSpeed(for: engine)
        switch engine {
        case .nghitts:
            // Cờ "Phiên âm tiếng Nhật" của NghiTTS (1.3.973) — của VieNeu là `names` bên dưới.
            let japanese = TTSJapaneseTransliterationSettings.isEnabled(forTool: TTSJapaneseTransliterationSettings.nghiTool)
            return "nghitts|\(nghiVoice)|\(speed)|\(japanese)"
        case .vieneu:
            let synthesis = VieNeuSynthesisPolicy.synthesisSpeed(from: defaults)
            let dictionary = defaults.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey)
            let names = VieNeuJapaneseNameReader.isEnabled
            let nameBoost = VieNeuNameFrameBoost.mode.rawValue
            return "vieneu|\(VieNeuVoiceSelection.stored.storageValue)|\(speed)|\(synthesis)|\(dictionary)|\(names)|\(nameBoost)"
        case .vtts:
            let japanese = TTSJapaneseTransliterationSettings.isEnabled(forTool: TTSJapaneseTransliterationSettings.vttsTool)
            // "vtts tự đọc nhanh tối đa" (1.3.1037) đổi tiếng vtts tạo ra như tốc độ.
            // Công tắc "Áp dụng từ điển phiên âm vtts" (1.3.1041) đổi chữ đưa vào vtts.
            let dictionary = VttsPhoneticDictionary.isEnabled
            return "vtts|\(TTSManager.storedVttsVoice)|\(speed)|\(TTSManager.vttsNativeSpeedMax)|\(japanese)|\(dictionary)"
        }
    }
}
