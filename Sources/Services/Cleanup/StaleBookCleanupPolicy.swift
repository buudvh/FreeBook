import Foundation

/// Nguồn **duy nhất** cho câu hỏi "có được tự động xoá truyện lâu không đọc lúc này không, và lâu là
/// bao lâu".
///
/// Cùng khuôn với [`DriveAutoBackupPolicy`](../Backup/DriveAutoBackupPolicy.swift) và
/// [`NewChapterCheckPolicy`](../NewChapters/NewChapterCheckPolicy.swift): hai chế độ `.cooldown` /
/// `.daily`, mốc lần chạy cuối nằm trong UserDefaults, mọi hằng và khoá khai ở đây chứ không nhân bản
/// sang coordinator hay view. Các khoá/giá trị mặc định là **của riêng** tính năng này — không dùng lại
/// hằng của hai policy kia.
///
/// Khác biệt quan trọng: cờ bật/tắt mặc định **tắt**. Sao lưu và kiểm tra chương mới chỉ tốn pin/mạng,
/// còn ở đây là **xoá dữ liệu không hoàn tác được** — người dùng phải tự bật, không được bật hộ.
enum StaleBookCleanupPolicy {
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

    static let enabledKey = "staleBookCleanupEnabled"
    static let modeKey = "staleBookCleanupMode"
    static let cooldownHoursKey = "staleBookCleanupCooldownHours"
    static let dailyHourKey = "staleBookCleanupDailyHour"
    static let inactiveDaysKey = "staleBookCleanupInactiveDays"
    private static let lastRunKey = "staleBookCleanupLastRunAt"

    /// Số ngày không đọc mặc định trước khi một truyện bị coi là bỏ quên.
    static let defaultInactiveDays = 30
    /// Biên kẹp của `inactiveDays`. Dưới 7 ngày là quá dễ mất truyện đang đọc dở vì một tuần nghỉ phép.
    static let inactiveDaysRange = 7...365

    /// Hoãn trước khi chạy lượt đầu sau khi mở app. Cố ý **dài hơn** 25s của lượt sao lưu Drive: hai
    /// lượt nền không được đấu nhau, và bản sao lưu phải chạy trước khi có gì bị xoá.
    static let startupDelayNanoseconds: UInt64 = 40_000_000_000

    static var isEnabled: Bool {
        // Mặc định `false`: đây là hành động xoá dữ liệu không hoàn tác được.
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? false }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    /// Ngưỡng "lâu không đọc", tính theo ngày kể từ `Book.lastReadDate`.
    static var inactiveDays: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: inactiveDaysKey) as? Int ?? defaultInactiveDays
            return clampInactiveDays(stored)
        }
        set { UserDefaults.standard.set(clampInactiveDays(newValue), forKey: inactiveDaysKey) }
    }

    static var mode: Mode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey), let mode = Mode(rawValue: raw) else {
                return .daily
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var cooldownHours: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: cooldownHoursKey) as? Int ?? 24
            return min(max(stored, 12), 336)
        }
        set { UserDefaults.standard.set(min(max(newValue, 12), 336), forKey: cooldownHoursKey) }
    }

    static var dailyHour: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: dailyHourKey) as? Int ?? 3
            return min(max(stored, 0), 23)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: dailyHourKey) }
    }

    static var lastRunAt: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    /// Cửa mở cho lượt tự động. Bấm "dọn ngay" trong Cài đặt **không** đi qua hàm này.
    static func shouldRun(now: Date = Date()) -> Bool {
        guard isEnabled else { return false }
        guard let last = lastRunAt else { return true }
        switch mode {
        case .cooldown:
            return now.timeIntervalSince(last) >= Double(cooldownHours) * 3600
        case .daily:
            guard let boundary = todayBoundary(now: now) else { return true }
            return now >= boundary && last < boundary
        }
    }

    /// Đánh dấu **lúc bắt đầu** lượt, không phải lúc thành công — giống bản Drive: một lượt lỗi (DB
    /// khoá, xoá file thất bại) không được biến mỗi lần mở app thành một lần quét toàn thư viện.
    static func markRun(now: Date = Date()) {
        lastRunAt = now
    }

    /// Mốc thời gian mà truyện có `lastReadDate` cũ hơn nó thì bị coi là bỏ quên.
    static func cutoffDate(now: Date = Date(), days: Int? = nil) -> Date? {
        let threshold = clampInactiveDays(days ?? inactiveDays)
        return Calendar.current.date(byAdding: .day, value: -threshold, to: now)
    }

    static func clampInactiveDays(_ value: Int) -> Int {
        min(max(value, inactiveDaysRange.lowerBound), inactiveDaysRange.upperBound)
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
