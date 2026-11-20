import Foundation

/// Ảnh chụp mọi cài đặt **ảnh hưởng tới tổng hợp** trước khi mở sheet Cài đặt TTS — tách khỏi `TTSManager`
/// (đợt 7, 1.3.486). `resumeAfterSettings` so hai ảnh chụp: bằng nhau ⇒ chỉ `resume()`, khác ⇒ dừng engine và
/// dựng lại đoạn. Danh sách trường là **có chủ ý**: cố ý **không** gồm `nghittsSafeCachedTimeThreshold`,
/// `nghittsPrefetchCount` và `vieneu*` — đổi riêng ngưỡng đệm không được làm phát lại từ đầu (rules.md).
/// Đừng "bổ sung cho đủ".
///
/// Ngoại lệ có chủ ý: `vieneuModel` (Nano / Turbo) — đổi model là đổi engine tổng hợp dù `tool` vẫn là `"vieneu"`, nên
/// phải dựng lại đoạn như khi đổi engine.
///
/// `japaneseTransliteration` (1.3.973) là công tắc "Phiên âm tiếng Nhật" của **trình đọc chính** — với VieNeu nó thay
/// `vieneuJapaneseNameSyllablesEnabled` và, khác các khoá `vieneu*` còn lại, **có** dựng lại đoạn (đổi chữ đưa vào engine).
///
/// `vttsNativeSpeedMax` (1.3.1037): "vtts tự đọc nhanh tối đa" — như `speed`, đổi là đổi tiếng vtts tạo ra (tốc độ đưa vào
/// model), nên đóng Cài đặt phải dựng lại đoạn + xoá đệm. Trình đọc khác đổi giá trị này cũng dựng lại (hiếm, vô hại).
///
/// Ngoại lệ thứ hai: `onlineFallback` (1.3.945) — cài đặt giọng dự phòng của trình đọc online (`TTSOnlineFallbackSettings`
/// `.fingerprint`); đổi ⇒ dựng lại đoạn để bỏ tiếng dự phòng đã nạp trước theo cài đặt cũ.
struct TTSSettingsSnapshot: Equatable {
    let tool: String
    let vieneuModel: String
    let selectedVoice: String
    let pitch: Double
    let speed: Double
    let chunkLength: Int
    let prefetchDelayMs: Int
    let googlePrefetchCount: Int
    let extPrefetchCount: Int
    let extensionLocalPath: String
    let extensionConfigJson: String
    let newlinePause: Double
    let sentencePause: Double
    let phrasePause: Double
    let bracketPause: Double
    let paragraphPause: Double
    let numericNormalization: Bool
    let dictionaryReplacement: Bool
    let transliteration: Bool
    /// "Phiên âm tiếng Nhật" của trình đọc chính (1.3.973, lưu riêng từng trình đọc) — đổi là đổi chữ đưa vào engine.
    let japaneseTransliteration: Bool
    let onlineFallback: String
    let vttsNativeSpeedMax: Double

    /// Đọc các khoá `UserDefaults` **tại thời điểm gọi** (hai thời điểm: `prepareForSettings`, `resumeAfterSettings`).
    static func capture(
        tool: String,
        selectedVoice: String,
        pitch: Double,
        speed: Double,
        chunkLength: Int,
        prefetchDelayMs: Int,
        googlePrefetchCount: Int,
        extPrefetchCount: Int,
        extensionLocalPath: String,
        extensionConfigJson: String
    ) -> TTSSettingsSnapshot {
        TTSSettingsSnapshot(
            tool: tool,
            vieneuModel: VieNeuModelChoice.current.rawValue,
            selectedVoice: selectedVoice,
            pitch: pitch,
            speed: speed,
            chunkLength: chunkLength,
            prefetchDelayMs: prefetchDelayMs,
            googlePrefetchCount: googlePrefetchCount,
            extPrefetchCount: extPrefetchCount,
            extensionLocalPath: extensionLocalPath,
            extensionConfigJson: extensionConfigJson,
            newlinePause: UserDefaults.standard.double(forKey: "newlinePauseDuration"),
            sentencePause: UserDefaults.standard.double(forKey: "sentencePauseDuration"),
            phrasePause: UserDefaults.standard.double(forKey: "phrasePauseDuration"),
            bracketPause: UserDefaults.standard.double(forKey: "bracketPauseDuration"),
            paragraphPause: UserDefaults.standard.double(forKey: "paragraphPauseDuration"),
            numericNormalization: UserDefaults.standard.object(forKey: PreprocessorSettingKey.numericNormalizationEnabled) as? Bool ?? true,
            dictionaryReplacement: UserDefaults.standard.object(forKey: PreprocessorSettingKey.dictionaryReplacementEnabled) as? Bool ?? true,
            transliteration: UserDefaults.standard.object(forKey: PreprocessorSettingKey.transliterationEnabled) as? Bool ?? true,
            japaneseTransliteration: TTSJapaneseTransliterationSettings.isEnabled(forTool: tool),
            onlineFallback: TTSOnlineFallbackSettings.fingerprint(mainTool: tool),
            vttsNativeSpeedMax: TTSManager.vttsNativeSpeedMax
        )
    }
}
