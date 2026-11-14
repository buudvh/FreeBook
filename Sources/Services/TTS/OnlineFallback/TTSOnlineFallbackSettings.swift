import Foundation

/// **Giọng dự phòng** khi TTS online (Google Cloud TTS / tiện ích TTS) lỗi (1.3.945, anh Bửu duyệt mockup): một trình đọc
/// offline — NghiTTS (Piper) hoặc VieNeu — chọn ở màn "Giọng dự phòng" (Cài đặt TTS › Khi giọng online lỗi).
///
/// Chỉ lưu **trình đọc nào** (`toolKey`, rỗng / thiếu = Không dùng). Giọng, tốc độ, tốc độ tổng hợp, từ điển phiên âm… là
/// cài đặt **của chính engine đó** (`nghittsVoice` / `VieNeuVoiceSelection`, `nghittsRate` / `vieneuRate`…) — chung với lúc
/// engine đó là trình đọc chính, nên màn "Giọng dự phòng" dựng y các mục của Cài đặt TTS khi chọn engine đó.
enum TTSOnlineFallbackSettings {
    enum Engine: String, CaseIterable, Identifiable, Sendable {
        case nghitts
        case vieneu

        var id: String { rawValue }
        var title: String { self == .nghitts ? "NghiTTS" : "VieNeu" }
        /// Chữ của Picker — trùng Picker "Trình đọc" của Cài đặt TTS.
        var pickerTitle: String { self == .nghitts ? "NghiTTS (Piper Offline)" : "VieNeu-TTS v3 (Offline)" }
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
        engine == .vieneu ? TTSManager.VieNeuSettingsKey.rate : "nghittsRate"
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
            return "nghitts|\(nghiVoice)|\(speed)"
        case .vieneu:
            let synthesis = VieNeuSynthesisPolicy.synthesisSpeed(from: defaults)
            let dictionary = defaults.bool(forKey: VieNeuJapanesePreprocessor.dictionaryEnabledKey)
            return "vieneu|\(VieNeuVoiceSelection.stored.storageValue)|\(speed)|\(synthesis)|\(dictionary)"
        }
    }
}
