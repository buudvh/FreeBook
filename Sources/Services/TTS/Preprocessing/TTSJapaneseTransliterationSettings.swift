import Foundation

/// Công tắc **"Phiên âm tiếng Nhật"** — có ở **mọi** trình đọc, lưu **riêng từng trình đọc** (1.3.973, anh Bửu: "sửa lại
/// nút phiên âm tiếng nhật cho tất cả tts, config lưu riêng mỗi loại tts").
///
/// ## Khoá
/// `ttsJapaneseTransliterationEnabled.<tool>` với `tool` đúng bằng `TTSManager.tool`: `system` (Siri), `nghitts`,
/// `vieneu` (Nano và Turbo chung một trình đọc), `google`, còn lại là `packageId` của tiện ích TTS — mỗi tiện ích một khoá.
///
/// ## Giá trị khi chưa có khoá theo trình đọc
/// - `nghitts`: lấy công tắc cũ "Phiên âm tiếng Anh/Nhật" (`preprocessorTransliterationEnabled`, thiếu = bật);
/// - `vieneu`: lấy công tắc cũ "Đọc tên Nhật theo âm tiết" (`vieneuJapaneseNameSyllablesEnabled`, thiếu = bật);
/// - Siri / Google / tiện ích: **tắt** — trước 1.3.973 các trình đọc này không phiên âm gì, giữ nguyên cách đọc cũ.
///
/// Hai trình đọc có khoá cũ được **chép sang khoá mới ở lần đọc đầu** (`isEnabled`): từ đó gạt công tắc cũ (nay chỉ còn
/// là "Phiên âm tiếng Anh" của NghiTTS) không kéo theo tiếng Nhật. Khoá cũ giữ nguyên, không xoá.
///
/// ## Mỗi trình đọc làm gì khi bật
/// - NghiTTS: nhánh tiếng Nhật của `TextPreprocessor` (kana → romaji, romaji → âm tiết Việt);
/// - VieNeu: tên kiểu Nhật viết hoa đọc theo âm tiết (`VieNeuJapaneseNameReader`);
/// - Siri / Google / tiện ích: `TTSJapaneseTextTransliterator` đổi chữ ngay trước khi đưa cho engine.
enum TTSJapaneseTransliterationSettings {
    static let keyPrefix = "ttsJapaneseTransliterationEnabled."

    static let nghiTool = "nghitts"
    static let vieNeuTool = "vieneu"
    static let siriTool = "system"
    static let googleTool = "google"

    static func key(forTool tool: String) -> String {
        keyPrefix + tool
    }

    /// Gọi được từ thread bất kỳ (chỉ đọc / ghi `UserDefaults`). Đường nóng: gọi cho từng đoạn trước khi tổng hợp.
    static func isEnabled(forTool tool: String, defaults: UserDefaults = .standard) -> Bool {
        let storageKey = key(forTool: tool)
        if let stored = defaults.object(forKey: storageKey) as? Bool { return stored }
        guard let legacy = legacyValue(forTool: tool, defaults: defaults) else { return false }
        defaults.set(legacy, forKey: storageKey)
        return legacy
    }

    static func setEnabled(_ enabled: Bool, forTool tool: String, defaults: UserDefaults = .standard) {
        defaults.set(enabled, forKey: key(forTool: tool))
    }

    /// Giá trị của công tắc cũ; `nil` = trình đọc chưa từng có công tắc phiên âm tiếng Nhật.
    private static func legacyValue(forTool tool: String, defaults: UserDefaults) -> Bool? {
        switch tool {
        case nghiTool:
            return defaults.object(forKey: PreprocessorSettingKey.transliterationEnabled) as? Bool ?? true
        case vieNeuTool:
            return defaults.object(forKey: VieNeuJapaneseNameReader.enabledKey) as? Bool ?? true
        default:
            return nil
        }
    }
}
