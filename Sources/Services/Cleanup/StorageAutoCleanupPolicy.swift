import Foundation

/// Nguồn **duy nhất** cho lịch **tự động dọn dung lượng** (1.3.762): bật/tắt, nhịp chạy và mục được dọn.
///
/// Cùng khuôn với [`DriveAutoBackupPolicy`](../Backup/DriveAutoBackupPolicy.swift) và
/// [`StaleBookCleanupPolicy`](StaleBookCleanupPolicy.swift): hai chế độ `.cooldown` / `.daily`, mốc lượt cuối trong
/// UserDefaults, mọi khoá + hằng khai ở đây (khoá là của riêng tính năng này). Màn
/// `StorageAutoCleanupSettingsView` bind `@AppStorage` đúng các khoá này.
///
/// Mặc định **bật, chỉ dọn bìa truyện** (bìa mồ côi + thu nhỏ bìa quá cỡ — không mất gì của người dùng), mỗi ngày sau
/// 03:00. Các mục khác người dùng tự bật. App không có tác vụ nền: lượt chạy lúc mở app khi đã tới kỳ.
enum StorageAutoCleanupPolicy {
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

    static let enabledKey = "storageAutoCleanupEnabled"
    static let modeKey = "storageAutoCleanupMode"
    static let cooldownHoursKey = "storageAutoCleanupCooldownHours"
    static let dailyHourKey = "storageAutoCleanupDailyHour"
    static let categoriesKey = "storageAutoCleanupCategories"
    private static let lastRunKey = "storageAutoCleanupLastRunAt"
    private static let lastFreedBytesKey = "storageAutoCleanupLastFreedBytes"

    static let defaultEnabled = true
    static let defaultMode = Mode.daily
    static let defaultCooldownHours = 24
    static let defaultDailyHour = 3
    static let cooldownHoursRange = 6...168
    static let defaultCategories: Set<StorageUsageCategory> = [.covers]

    /// Mục lịch được dọn, theo thứ tự hiện trên màn cài đặt. Bìa = dọn (mồ côi + thu nhỏ), còn lại = xoá cả loại như
    /// nút "Xoá" của màn Dung lượng (`StorageUsageCleaner`).
    static let eligibleCategories: [StorageUsageCategory] = [.covers, .comicImageCache, .exports, .logs, .checkReports]

    /// Hoãn sau khi mở app — dài hơn lượt sao lưu (25 s) và dọn truyện cũ (40 s): bản sao lưu chụp trước, các lượt
    /// nền không đấu nhau.
    static let startupDelayNanoseconds: UInt64 = 45_000_000_000

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? defaultEnabled }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static var mode: Mode {
        get {
            guard let raw = UserDefaults.standard.string(forKey: modeKey), let mode = Mode(rawValue: raw) else {
                return defaultMode
            }
            return mode
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: modeKey) }
    }

    static var cooldownHours: Int {
        get { clampCooldownHours(UserDefaults.standard.object(forKey: cooldownHoursKey) as? Int ?? defaultCooldownHours) }
        set { UserDefaults.standard.set(clampCooldownHours(newValue), forKey: cooldownHoursKey) }
    }

    static var dailyHour: Int {
        get { min(max(UserDefaults.standard.object(forKey: dailyHourKey) as? Int ?? defaultDailyHour, 0), 23) }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: dailyHourKey) }
    }

    /// Lưu dạng mảng rawValue; mục lạ / không còn đủ điều kiện bị bỏ qua. Chưa từng lưu ⇒ `defaultCategories`.
    static var categories: Set<StorageUsageCategory> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: categoriesKey) as? [String] else { return defaultCategories }
            return Set(raw.compactMap { StorageUsageCategory(rawValue: $0) }).intersection(eligibleCategories)
        }
        set {
            let raw = newValue.intersection(eligibleCategories).map(\.rawValue).sorted()
            UserDefaults.standard.set(raw, forKey: categoriesKey)
        }
    }

    static var lastRunAt: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    /// Dung lượng giải phóng ở lượt gần nhất (tự động hoặc bấm "Dọn ngay"); `nil` ⇒ chưa chạy lượt nào.
    static var lastFreedBytes: Int64? {
        get { (UserDefaults.standard.object(forKey: lastFreedBytesKey) as? NSNumber)?.int64Value }
        set { UserDefaults.standard.set(newValue.map { NSNumber(value: $0) }, forKey: lastFreedBytesKey) }
    }

    static func clampCooldownHours(_ hours: Int) -> Int {
        min(max(hours, cooldownHoursRange.lowerBound), cooldownHoursRange.upperBound)
    }

    /// Cửa mở cho lượt tự động. Nút "Dọn ngay" bỏ qua hàm này.
    static func shouldRun(now: Date = Date()) -> Bool {
        guard isEnabled, !categories.isEmpty else { return false }
        guard let last = lastRunAt else { return true }
        switch mode {
        case .cooldown:
            return now.timeIntervalSince(last) >= Double(cooldownHours) * 3600
        case .daily:
            guard let boundary = todayBoundary(now: now) else { return true }
            return now >= boundary && last < boundary
        }
    }

    /// Đánh dấu **lúc bắt đầu** lượt: một lượt lỗi không biến mỗi lần mở app thành một lượt dọn.
    static func markRun(now: Date = Date()) {
        lastRunAt = now
    }

    /// "Tắt" / "Mỗi ngày, sau 03:00" / "Cách nhau 24 giờ" — hàng lối vào ở màn Dung lượng.
    static func summary(isEnabled: Bool, mode: Mode, cooldownHours: Int, dailyHour: Int) -> String {
        guard isEnabled else { return "Tắt" }
        switch mode {
        case .cooldown: return "Cách nhau \(clampCooldownHours(cooldownHours)) giờ"
        case .daily: return "Mỗi ngày, sau \(String(format: "%02d:00", min(max(dailyHour, 0), 23)))"
        }
    }

    /// Tên mục trên màn cài đặt lịch (khác tên hàng của màn Dung lượng ở chỗ nói rõ dọn gì).
    static func title(for category: StorageUsageCategory) -> String {
        switch category {
        case .covers: return "Bìa mồ côi + thu nhỏ bìa quá cỡ"
        case .exports: return "File xuất đã xong"
        default: return category.title
        }
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
