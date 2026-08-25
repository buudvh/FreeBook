import Foundation

/// Nguồn **duy nhất** cho câu hỏi "có được tự động sao lưu lên Google Drive lúc này không".
///
/// Cùng khuôn với [`NewChapterCheckPolicy`](../NewChapters/NewChapterCheckPolicy.swift): hai chế độ
/// `.cooldown` / `.daily`, mốc lần chạy cuối nằm trong UserDefaults, và mọi hằng chặn tải khai ở đây
/// chứ không nhân bản sang coordinator hay view.
///
/// Lượt tự động chỉ chạy khi đã đăng nhập Drive — nên cờ mặc định bật: bản thân việc đăng nhập
/// Drive đã là hành động cố ý của người dùng.
enum DriveAutoBackupPolicy {
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

    static let enabledKey = "driveAutoBackupEnabled"
    static let modeKey = "driveAutoBackupMode"
    static let cooldownHoursKey = "driveAutoBackupCooldownHours"
    static let dailyHourKey = "driveAutoBackupDailyHour"
    static let scopesKey = "driveAutoBackupScopes"
    private static let lastRunKey = "driveAutoBackupLastRunAt"
    private static let lastLinkWarningKey = "driveAutoBackupLastLinkWarningAt"

    /// Khoảng cách tối thiểu giữa hai lời nhắc "đang bật tự động mà chưa đăng nhập Drive".
    private static let linkWarningCooldown: TimeInterval = 24 * 3600

    /// Số bản `freebook-auto-*.fbbackup` được giữ lại trên Drive **và** trong máy. Bản thứ 6 trở đi
    /// (cũ nhất trước) bị xoá ngay sau khi bản mới tải lên xong.
    static let maxVersions = 5

    /// Hoãn trước khi chạy lượt đầu sau khi mở app: nén archive + upload là việc nặng, để nó đấu
    /// với lúc khởi động (nạp từ điển, kiểm tra chương mới) là làm app giật ngay khi vừa mở.
    static let startupDelayNanoseconds: UInt64 = 25_000_000_000

    /// Nhóm nội dung mặc định cho lượt **tự động**: đủ để dựng lại thư viện mà archive vẫn nhỏ.
    /// Cố ý bỏ `.content` (chương tải offline) và `.dictShared` (từ điển chung vài trăm MB) — hai
    /// nhóm này tải lại được, mà lượt tự động thì chạy hằng ngày trên mạng của người dùng.
    static let defaultScopes: Set<BackupScope> = [.books, .extensions, .dictBooks, .dictCustom]

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
            let stored = UserDefaults.standard.object(forKey: cooldownHoursKey) as? Int ?? 24
            return min(max(stored, 6), 168)
        }
        set { UserDefaults.standard.set(min(max(newValue, 6), 168), forKey: cooldownHoursKey) }
    }

    static var dailyHour: Int {
        get {
            let stored = UserDefaults.standard.object(forKey: dailyHourKey) as? Int ?? 22
            return min(max(stored, 0), 23)
        }
        set { UserDefaults.standard.set(min(max(newValue, 0), 23), forKey: dailyHourKey) }
    }

    /// Lưu dạng mảng rawValue để thêm case `BackupScope` về sau không làm vỡ giá trị cũ.
    /// `books` luôn được thêm lại vì mọi nhóm khác tra theo slug của nó.
    static var scopes: Set<BackupScope> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: scopesKey) as? [String] else {
                return defaultScopes
            }
            let parsed = Set(raw.compactMap { BackupScope(rawValue: $0) })
            return parsed.isEmpty ? defaultScopes : parsed.union([.books])
        }
        set {
            let raw = newValue.union([.books]).map { $0.rawValue }.sorted()
            UserDefaults.standard.set(raw, forKey: scopesKey)
        }
    }

    static var lastRunAt: Date? {
        get { UserDefaults.standard.object(forKey: lastRunKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastRunKey) }
    }

    /// Cửa mở cho lượt tự động. Bấm "sao lưu lên Drive ngay" **không** đi qua hàm này.
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

    /// Đánh dấu **lúc bắt đầu** lượt, không phải lúc thành công: một lần thất bại (mất mạng, Drive
    /// từ chối) không được biến mỗi lần mở app thành một lần nén archive vô ích.
    static func markRun(now: Date = Date()) {
        lastRunAt = now
    }

    /// Cửa mở cho **lời nhắc**, không phải cho lượt sao lưu: lượt đã tới kỳ mà Drive chưa đăng nhập
    /// thì im lặng là mất hẳn tín hiệu (dấu hiệu duy nhất còn lại nằm trong Cài đặt), nhưng nhắc mỗi
    /// lần mở app thì thành spam.
    ///
    /// Cố ý **không** dùng `lastRunAt`/`markRun()` cho việc này: một lời nhắc không được tính là một
    /// lượt sao lưu, nếu không thì ngay sau khi đăng nhập lại người dùng còn phải chờ hết cooldown
    /// mới có bản sao lưu đầu tiên.
    static func shouldWarnDriveNotLinked(now: Date = Date()) -> Bool {
        guard let last = UserDefaults.standard.object(forKey: lastLinkWarningKey) as? Date else { return true }
        return now.timeIntervalSince(last) >= linkWarningCooldown
    }

    static func markDriveNotLinkedWarned(now: Date = Date()) {
        UserDefaults.standard.set(now, forKey: lastLinkWarningKey)
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
