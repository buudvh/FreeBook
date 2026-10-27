import Foundation

/// Bộ xoay tài khoản Google cho **một** lần chạy (quét tên riêng hoặc một lượt chat Reader) — 1.3.614, thay
/// `AINameScanProviderSwitch` của 1.3.612.
///
/// Google giới hạn số câu trả lời AI theo **tài khoản**. Mỗi profile `googleAIMode` là một tài khoản
/// (`GoogleAccountSnapshot`), nên khi bị giới hạn:
/// 1. chuyển sang profile Chế độ AI **kế tiếp** trong danh sách chưa bị giới hạn trong lần chạy này;
/// 2. hết tài khoản Chế độ AI ⇒ chuyển sang profile **Gemini Web** nếu có (giữ nguyên hành vi 1.3.612);
/// 3. không có gì để chuyển ⇒ chờ theo nấc `rateLimitWaits` (1 → 2 → 4 → 8 phút), hết nấc thì dừng.
///
/// Lượt thành công đưa nấc chờ về 0 và xoá danh sách tài khoản đã bị giới hạn. Hai lượt liên tiếp "Chế độ AI báo lỗi"
/// (`generationFailed`) cũng tính là bị giới hạn — người dùng gặp đúng lỗi này khi Google chặn.
///
/// Class có khoá vì vòng lượt chạy trong Task nền; đọc Keychain để biết profile nào thật sự có phiên.
final class GoogleAccountRotation: @unchecked Sendable {
    /// Nấc chờ khi không còn tài khoản nào để chuyển (giây).
    static let rateLimitWaits: [TimeInterval] = [60, 120, 240, 480]

    private let lock = NSLock()
    private var current: AIConfiguration
    private var limitedProfileIds: Set<String> = []
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

    /// Tên profile đã chuyển sang (tài khoản Google hoặc Gemini Web); `nil` = chưa chuyển.
    var switchedProviderName: String? {
        lock.lock(); defer { lock.unlock() }
        return switchedName
    }

    /// Tổng số phút đã chờ khi hết nấc (cho thông điệp dừng).
    static var totalWaitMinutes: Int {
        Int(rateLimitWaits.reduce(0, +) / 60)
    }

    /// Lượt xong (có tên hoặc "Không có name"): về nấc chờ 0, xoá đếm lỗi liên tiếp và danh sách tài khoản bị giới hạn.
    func recordSuccess() {
        lock.lock(); defer { lock.unlock() }
        waitLevel = 0
        consecutiveGenerationFailures = 0
        limitedProfileIds.removeAll()
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

    /// Chuyển sang tài khoản Google kế tiếp **chưa bị giới hạn và có snapshot phiên**, vòng tròn theo thứ tự danh sách
    /// profile. `nil` = không còn tài khoản nào (hoặc đang không chạy Chế độ AI).
    ///
    /// Đánh dấu tài khoản đang dùng là đã bị giới hạn ngay khi gọi — người gọi phải gọi `rollbackSwitch(to:)` nếu tráo
    /// cookie thất bại.
    func rotateToNextAccount() -> AIProviderProfile? {
        lock.lock(); defer { lock.unlock() }
        guard current.activeProfile.isGoogleAIMode else { return nil }
        let currentId = current.activeProfileId
        limitedProfileIds.insert(currentId)

        let accounts = current.profiles.filter { $0.isGoogleAIMode }
        guard accounts.count > 1, let start = accounts.firstIndex(where: { $0.id == currentId }) else { return nil }
        for offset in 1...accounts.count {
            let candidate = accounts[(start + offset) % accounts.count]
            guard candidate.id != currentId, !limitedProfileIds.contains(candidate.id) else { continue }
            guard GoogleAccountSnapshotStore.load(profileId: candidate.id) != nil else { continue }
            current.activeProfileId = candidate.id
            switchedName = candidate.name
            consecutiveGenerationFailures = 0
            return candidate
        }
        return nil
    }

    /// Tráo cookie thất bại ⇒ trả con trỏ về profile cũ để lần sau còn thử lại.
    func rollbackSwitch(to profileId: String) {
        lock.lock(); defer { lock.unlock() }
        current.activeProfileId = profileId
        switchedName = nil
    }

    /// Chuyển sang profile Gemini Web đầu tiên — bước cuối trước khi phải chờ. `nil` khi không có hoặc đang không chạy
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
