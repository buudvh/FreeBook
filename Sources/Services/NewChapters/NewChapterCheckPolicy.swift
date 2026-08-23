import Foundation

/// Nguồn **duy nhất** cho câu hỏi "có được kiểm tra chương mới lúc này không".
///
/// Hai chế độ, cùng một mục đích là không bắn request mỗi lần mở app:
/// * `.cooldown` — kiểm tra lại sau `cooldownHours` giờ kể từ lần trước.
/// * `.daily` — mỗi ngày đúng một lượt, chỉ sau giờ người dùng chọn (`dailyHour`).
///
/// Các hằng chặn tải nằm ở đây, **không** nhân bản sang manager hay probe.
enum NewChapterCheckPolicy {
    enum Mode: String, CaseIterable, Sendable {
        case cooldown
        case daily

        var displayName: String {
            switch self {
            case .cooldown: return "Theo chu kỳ"
            case .daily: return "Mỗi ngày một lần"
            }
        }
    }

    static let enabledKey = "newChapterCheckEnabled"
    static let modeKey = "newChapterCheckMode"
    static let cooldownHoursKey = "newChapterCooldownHours"
    static let dailyHourKey = "newChapterDailyHour"
    private static let lastBatchKey = "newChapterLastBatchAt"

    /// Số truyện tối đa cho một lượt kiểm tra tự động (ưu tiên truyện đọc gần đây nhất).
    static let maxBooksPerBatch = 20
    /// Mục lục phân trang quá số này thì chỉ lấy **trang cuối** thay vì mọi trang: một truyện 50 trang
    /// là 50 request, nhân với số truyện trên kệ là không chấp nhận được cho một lượt kiểm tra ngầm.
    static let maxTOCPagesPerCheck = 8
    /// Nghỉ giữa hai truyện để lượt kiểm tra ngầm không đấu băng thông với việc đọc/tải của người dùng.
    static let interBookDelayNanoseconds: UInt64 = 400_000_000

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var mode: Mode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey), let mode = Mode(rawValue: raw) else {
                return .cooldown
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var cooldownHours: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: cooldownHoursKey) as? Int ?? 6
            return min(max(stored, 1), 48)
        }
        set { UserDefaults.standard.set(min(max(newValue, 1), 48), forKey: cooldownHoursKey) }
    }

    static var dailyHour: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: dailyHourKey) as? Int ?? 8
            return min(max(stored, 0), 23)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: dailyHourKey) }
    }

    static var lastBatchAt: Date? {
        get { UserDefaults.standard.object(forKey: lastBatchKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastBatchKey) }
    }

    /// Cửa mở cho **cả lượt** kiểm tra tự động. Refresh tay không đi qua hàm này.
    static func shouldRunBatch(now: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        guard let last = lastBatchAt else { return true }
        switch mode {
        case .cooldown:
            return now.timeIntervalSince(last) >= Double(cooldownHours) * 3600
        case .daily:
            guard let boundary = todayBoundary(now: now) else { return true }
            return now >= boundary && last < boundary
        }
    }

    /// Cửa mở cho **một truyện** trong lượt: truyện vừa được kiểm tra tay xong không bị kiểm tra lại.
    static func shouldCheck(record: NewChapterRecord?, now: Date = Date()) -> Bool {
        guard let checkedAt = record?.lastCheckedAt else { return true }
        switch mode {
        case .cooldown:
            return now.timeIntervalSince(checkedAt) >= Double(cooldownHours) * 3600
        case .daily:
            guard let boundary = todayBoundary(now: now) else { return true }
            return checkedAt < boundary
        }
    }

    static func markBatchRun(now: Date = Date()) {
        lastBatchAt = now
    }

    /// Mốc `dailyHour` giờ của **hôm nay** theo lịch/múi giờ máy.
    private static func todayBoundary(now: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: now)
        components.hour = dailyHour
        components.minute = 0
        components.second = 0
        return Calendar.current.date(from: components)
    }
}
