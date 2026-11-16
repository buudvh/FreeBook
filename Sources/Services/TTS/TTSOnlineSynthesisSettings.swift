import Foundation

/// Cấu hình chung cho **TTS online** (Google Cloud TTS / TTS tiện ích): số lần thử lại + timeout mỗi lượt thử.
///
/// Trước 1.3.953 mỗi engine tự quyết: `ExtTTSService` retry cứng 2 lượt, Google TTS không retry, và không có
/// giới hạn thời gian chờ nào (fetch của extension mặc định 15 s, script tự đặt tới 120 s) ⇒ thời gian im lặng
/// không kiểm soát được. Nay gộp về một chỗ, đặt ở Cài đặt TTS (mục chung, chỉ hiện khi trình đọc chính là online).
///
/// Thử lại + timeout do **một** tầng áp: `RemoteTTSSynthesisCoordinator` (`RemoteTTSAttemptPolicy`, 1.3.960) — kể cả
/// Google TTS (bỏ vòng thử riêng 2 lượt của `GoogleTTSService`).
///
/// Khi **đã chọn giọng dự phòng offline** (1.3.960, anh Bửu chọn "7 s + thử lại 1 + song song" sau khi xem log: lượt
/// online thành công chậm nhất 6,8 s, timeout cứng 3 s của 1.3.953 cắt nhầm lượt sắp xong rồi chuyển cả phiên):
/// - timeout **theo cài đặt** như khi không có dự phòng;
/// - thử lại **khoá ở 1 lần**, áp cho **cả** lượt nạp trước — chỉ chuyển cả phiên sang dự phòng khi hết lượt thử hoặc
///   mất mạng;
/// - đoạn đang đọc quá `fallbackHedgeDelaySeconds` chưa có tiếng ⇒ tổng hợp song song bằng giọng dự phòng, bên nào xong
///   trước phát bên đó (`TTSManager+OnlineFallbackHedge`).
enum TTSOnlineSynthesisSettings {
    /// Số lần **thử lại** (0 = chỉ thử một lần). Mặc định 3.
    static let retryCountKey = "ttsOnlineRetryCount"
    /// Timeout **mỗi lượt thử** (giây). Mặc định 7.
    static let timeoutSecondsKey = "ttsOnlineTimeoutSeconds"

    static let retryRange = 0...5
    static let timeoutRange = 5...20
    static let defaultRetryCount = 3
    static let defaultTimeoutSeconds = 7
    /// Số lần thử lại cố định khi đã có giọng dự phòng offline (cả đoạn đang đọc lẫn lượt nạp trước).
    static let fallbackRetryCount = 1
    /// Đoạn đang đọc chờ online bấy nhiêu giây chưa có tiếng ⇒ tổng hợp song song bằng giọng dự phòng.
    static let fallbackHedgeDelaySeconds: TimeInterval = 3

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

    /// Đã cấu hình giọng dự phòng offline ⇒ thử lại khoá ở `fallbackRetryCount`.
    static var hasOfflineFallback: Bool {
        TTSOnlineFallbackSettings.engine != nil
    }

    /// Số lần thử lại **hiệu lực** của đoạn đang đọc: có giọng dự phòng thì `fallbackRetryCount`.
    static var effectiveRetryCount: Int {
        hasOfflineFallback ? fallbackRetryCount : storedRetryCount
    }

    /// Số lần thử lại của lượt **nạp trước**: không có dự phòng thì 0 (như 1.3.953 — server chết thì thử lại chỉ tốn
    /// slot); có dự phòng thì `fallbackRetryCount` — một lượt hụt chưa đủ để kết luận server chết rồi chuyển cả phiên.
    static var prefetchRetryCount: Int {
        hasOfflineFallback ? fallbackRetryCount : 0
    }

    /// Timeout mỗi lượt thử (giây) — theo cài đặt, có hay không có giọng dự phòng.
    static var effectiveTimeoutSeconds: Int {
        storedTimeoutSeconds
    }
}
