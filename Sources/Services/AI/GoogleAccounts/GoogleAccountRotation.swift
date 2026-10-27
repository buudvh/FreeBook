import Foundation

/// Bộ xoay **tài khoản Google** trong một provider Chế độ AI, cho một lần chạy (quét tên riêng hoặc một lượt chat Reader)
/// — 1.3.616, thay bản xoay theo profile của 1.3.615.
///
/// Google giới hạn số câu trả lời AI theo **tài khoản**, mà provider Chế độ AI giữ nhiều tài khoản
/// (`GoogleAccountStore.accounts(forProfileId:)`). Khi bị giới hạn:
/// 1. chuyển sang tài khoản **kế tiếp** trong provider chưa bị giới hạn ở lần chạy này (vòng tròn theo `order`);
/// 2. hết tài khoản ⇒ chuyển sang profile **Gemini Web** nếu có (giữ nguyên hành vi 1.3.612);
/// 3. không có gì để chuyển ⇒ chờ theo nấc `rateLimitWaits` (1 → 2 → 4 → 8 phút), hết nấc thì dừng.
///
/// Lượt thành công đưa nấc chờ về 0 và xoá danh sách tài khoản đã bị giới hạn. Hai lượt liên tiếp "Chế độ AI báo lỗi"
/// (`generationFailed`) cũng tính là bị giới hạn — người dùng gặp đúng lỗi này khi Google chặn.
///
/// **Không** đổi `activeProfileId`: provider vẫn là một, chỉ tài khoản bên trong đổi — nên Cài đặt không tự nhảy provider.
/// Class có khoá vì vòng lượt chạy trong Task nền.
final class GoogleAccountRotation: @unchecked Sendable {
    /// Nấc chờ khi không còn tài khoản nào để chuyển (giây).
    static let rateLimitWaits: [TimeInterval] = [60, 120, 240, 480]

    private let lock = NSLock()
    private var current: AIConfiguration
    private var limitedAccountIds: Set<String> = []
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

    /// Nhãn tài khoản (hoặc tên profile Gemini Web) đã chuyển sang; `nil` = chưa chuyển.
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
        limitedAccountIds.removeAll()
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

    /// Tài khoản kế tiếp **chưa bị giới hạn** trong provider đang dùng, vòng tròn từ tài khoản đang dùng. `nil` = không
    /// còn (hoặc provider chỉ có một tài khoản).
    ///
    /// Đánh dấu tài khoản đang dùng là đã bị giới hạn ngay khi gọi. Người gọi chỉ cần `GoogleSessionSwitcher.apply(account:)`
    /// — hàm đó tự khôi phục tài khoản cũ nếu tráo hỏng.
    func rotateToNextAccount() -> GoogleAccount? {
        lock.lock(); defer { lock.unlock() }
        guard current.activeProfile.isGoogleAIMode else { return nil }
        let profileId = current.activeProfileId
        let accounts = GoogleAccountStore.accounts(forProfileId: profileId)
        guard let startId = GoogleAccountStore.currentAccountId(forProfileId: profileId) ?? accounts.first?.id,
              let start = accounts.firstIndex(where: { $0.id == startId }) else { return nil }
        limitedAccountIds.insert(startId)
        guard accounts.count > 1 else { return nil }

        for offset in 1...accounts.count {
            let candidate = accounts[(start + offset) % accounts.count]
            guard candidate.id != startId, !limitedAccountIds.contains(candidate.id) else { continue }
            switchedName = candidate.label
            consecutiveGenerationFailures = 0
            return candidate
        }
        return nil
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
