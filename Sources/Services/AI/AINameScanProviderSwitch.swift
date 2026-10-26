import Foundation

/// Provider đang dùng cho **một** lần quét tên riêng nhiều chương (1.3.612) — dùng chung giữa vòng quét chính, vòng tự
/// thử lại ở cuối và nút "Thử lại k lượt lỗi".
///
/// Chế độ AI của Google bị giới hạn số câu trả lời AI ⇒ người dùng chọn: có profile Gemini Web thì **chuyển ngay** sang
/// đó cho phần còn lại của lần quét; không có thì chờ theo nấc `rateLimitWaits` (1 → 2 → 4 → 8 phút), hết nấc thì dừng.
/// Lượt thành công đưa nấc chờ về 0. Hai lượt liên tiếp "Chế độ AI báo lỗi" (`generationFailed`) cũng tính là bị giới
/// hạn — người dùng gặp đúng lỗi này khi Google chặn. Class có khoá vì vòng lượt chạy trong Task nền.
final class AINameScanProviderSwitch: @unchecked Sendable {
    /// Nấc chờ khi không có Gemini Web (giây).
    static let rateLimitWaits: [TimeInterval] = [60, 120, 240, 480]

    private let lock = NSLock()
    private var current: AIConfiguration
    private var switchedName: String?
    private var waitLevel = 0
    private var consecutiveGenerationFailures = 0

    init(config: AIConfiguration) {
        current = config
    }

    /// Cấu hình dùng cho lượt sắp gửi.
    var config: AIConfiguration {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    /// Tên profile Gemini Web đã chuyển sang; `nil` = chưa chuyển.
    var switchedProviderName: String? {
        lock.lock(); defer { lock.unlock() }
        return switchedName
    }

    /// Tổng số phút đã chờ khi hết nấc (cho thông điệp dừng).
    static var totalWaitMinutes: Int {
        Int(rateLimitWaits.reduce(0, +) / 60)
    }

    /// Lượt xong (có tên hoặc "Không có name"): về nấc chờ 0, xoá đếm lỗi liên tiếp.
    func recordSuccess() {
        lock.lock(); defer { lock.unlock() }
        waitLevel = 0
        consecutiveGenerationFailures = 0
    }

    /// Lỗi của Chế độ AI có phải dấu hiệu bị giới hạn không — `rateLimited`, hoặc `generationFailed` lần thứ hai liên
    /// tiếp. Lỗi khác xoá đếm `generationFailed`.
    func treatsAsRateLimit(_ error: GoogleAIModeError) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if error.isRateLimit { return true }
        guard error == .generationFailed else {
            consecutiveGenerationFailures = 0
            return false
        }
        consecutiveGenerationFailures += 1
        return consecutiveGenerationFailures >= 2
    }

    /// Chuyển sang profile Gemini Web đầu tiên của cấu hình; trả tên profile, `nil` khi không có hoặc đang không chạy
    /// Chế độ AI.
    func switchToGeminiWeb() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard current.activeProfile.isGoogleAIMode,
              let gemini = current.profiles.first(where: { $0.isGeminiWeb }) else { return nil }
        current.activeProfileId = gemini.id
        switchedName = gemini.name
        consecutiveGenerationFailures = 0
        return gemini.name
    }

    /// Nấc chờ kế tiếp — `nil` khi đã hết nấc.
    func nextWait() -> (seconds: TimeInterval, attempt: Int, total: Int)? {
        lock.lock(); defer { lock.unlock() }
        guard waitLevel < Self.rateLimitWaits.count else { return nil }
        let seconds = Self.rateLimitWaits[waitLevel]
        waitLevel += 1
        return (seconds, waitLevel, Self.rateLimitWaits.count)
    }
}
