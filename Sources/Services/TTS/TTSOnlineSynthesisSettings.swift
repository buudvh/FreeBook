import Foundation

/// Cấu hình chung cho **TTS online** (Google Cloud TTS / TTS tiện ích): số lần thử lại + timeout mỗi lượt thử.
///
/// Trước 1.3.953 mỗi engine tự quyết: `ExtTTSService` retry cứng 2 lượt, Google TTS không retry, và không có
/// giới hạn thời gian chờ nào (fetch của extension mặc định 15 s, script tự đặt tới 120 s) ⇒ thời gian im lặng
/// không kiểm soát được. Nay gộp về một chỗ, đặt ở Cài đặt TTS (mục chung, chỉ hiện khi trình đọc chính là online).
///
/// Khi **đã chọn giọng dự phòng offline** thì hai giá trị bị khoá: timeout cố định **3 s** và **không** thử lại
/// (retry = 0) — lúc đó đã có tiếng thay thế, hết 3 s là chuyển sang giọng dự phòng.
enum TTSOnlineSynthesisSettings {
    /// Số lần **thử lại** (0 = chỉ thử một lần). Mặc định 3.
    static let retryCountKey = "ttsOnlineRetryCount"
    /// Timeout **mỗi lượt thử** (giây). Mặc định 7.
    static let timeoutSecondsKey = "ttsOnlineTimeoutSeconds"

    static let retryRange = 0...5
    static let timeoutRange = 5...20
    static let defaultRetryCount = 3
    static let defaultTimeoutSeconds = 7
    /// Timeout cố định khi đã có giọng dự phòng offline — hết giờ là chuyển sang giọng dự phòng.
    static let fallbackTimeoutSeconds = 3

    /// Số lần thử lại đã lưu (chưa lưu ⇒ mặc định). Giá trị ngoài khoảng ⇒ coi như mặc định.
    static var storedRetryCount: Int {
        get {
            guard let value = UserDefaults.standard.object(forKey: retryCountKey) as? Int else { return defaultRetryCount }
            return retryRange.contains(value) ? value : defaultRetryCount
        }
        set { UserDefaults.standard.set(newValue, forKey: retryCountKey) }
    }

    /// Timeout mỗi lượt thử đã lưu (chưa lưu ⇒ mặc định). Giá trị ngoài khoảng ⇒ coi như mặc định.
    static var storedTimeoutSeconds: Int {
        get {
            guard let value = UserDefaults.standard.object(forKey: timeoutSecondsKey) as? Int else { return defaultTimeoutSeconds }
            return timeoutRange.contains(value) ? value : defaultTimeoutSeconds
        }
        set { UserDefaults.standard.set(newValue, forKey: timeoutSecondsKey) }
    }

    /// Đã cấu hình giọng dự phòng offline ⇒ khoá cấu hình (timeout 3 s, không thử lại).
    static var hasOfflineFallback: Bool {
        TTSOnlineFallbackSettings.engine != nil
    }

    /// Số lần thử lại **hiệu lực**: có giọng dự phòng thì 0 (đã có tiếng thay thế, không cần chờ thử lại).
    static var effectiveRetryCount: Int {
        hasOfflineFallback ? 0 : storedRetryCount
    }

    /// Timeout **hiệu lực** cho mỗi lượt thử (giây): có giọng dự phòng thì cố định 3 s.
    static var effectiveTimeoutSeconds: Int {
        hasOfflineFallback ? fallbackTimeoutSeconds : storedTimeoutSeconds
    }
}
