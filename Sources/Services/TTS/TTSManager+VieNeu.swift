import Foundation

/// Nối engine **VieNeu-TTS** vào đường đọc truyện.
///
/// Tách file vì `TTSManager.swift` đang **4026/3470** dòng (luật ratchet-down cấm thêm dòng) — extension
/// không thêm được stored property, nên chỗ này chỉ dùng **computed property**.
extension TTSManager {
    /// Khoá `UserDefaults` của engine VieNeu. Tách khỏi khoá `nghitts*` vì ngưỡng đệm là **hiệu năng**
    /// (mỗi engine một đặc tính RTF), còn khoảng nghỉ là **nội dung** nên vẫn dùng chung khoá `nghitts*`.
    enum VieNeuSettingsKey {
        static let voice = "vieneuVoice"
        static let rate = "vieneuRate"
        static let prefetchCount = "vieneuPrefetchCount"
        static let safeCachedTimeThreshold = "vieneuSafeCachedTimeThreshold"
    }

    /// Engine local đang chọn.
    ///
    /// **Tính chất an toàn của lượt nối này**: trả `nghiTTSService` cho **mọi** tool trừ `vieneu`, nên
    /// đường NghiTTS đi y hệt code cũ. Nếu sửa hàm này, phải giữ nguyên tính chất đó.
    internal var localEngine: (any LocalTTSEngine)? {
        tool == "vieneu" ? VieNeuTTSService.shared : nghiTTSService
    }

    /// Nạp tham số riêng của VieNeu khi Picker đổi sang `vieneu`.
    ///
    /// Gọi từ nhánh `else` của `loadParamsForCurrentTool()` — **một dòng** duy nhất phải thêm vào file
    /// legacy, phần thân nằm ở đây.
    internal func applyVieNeuParamsIfNeeded() {
        guard tool == "vieneu" else { return }
        let defaults = UserDefaults.standard

        let defaultRate = defaults.object(forKey: "ttsRate") != nil ? defaults.double(forKey: "ttsRate") : 1.0
        let savedRate = defaults.double(forKey: VieNeuSettingsKey.rate)
        self.speed = savedRate > 0 ? savedRate : defaultRate

        let voices = (try? VieNeuTTSService.shared?.availableVoices()) ?? []
        self.selectedVoice = defaults.string(forKey: VieNeuSettingsKey.voice) ?? voices.first?.name ?? ""

        let savedCount = defaults.object(forKey: VieNeuSettingsKey.prefetchCount) != nil
            ? defaults.integer(forKey: VieNeuSettingsKey.prefetchCount)
            : 3
        self.vieneuPrefetchCount = max(2, min(10, savedCount))

        let savedThreshold = defaults.object(forKey: VieNeuSettingsKey.safeCachedTimeThreshold) != nil
            ? defaults.double(forKey: VieNeuSettingsKey.safeCachedTimeThreshold)
            : NghiSynthesisPolicy.defaultSafeCachedTimeThreshold
        let clamped = NghiSynthesisPolicy.clampSafeCachedTimeThreshold(savedThreshold)
        self.vieneuSafeCachedTimeThreshold = clamped
        defaults.set(clamped, forKey: VieNeuSettingsKey.safeCachedTimeThreshold)

        // VieNeu không dùng chunkLength của Piper: nó tự tách chunk ở `VieNeuConfig.maxChunkCharacters`.
        self.prefetchDelayMs = 500
    }
}
