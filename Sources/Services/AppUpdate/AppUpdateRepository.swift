import Foundation
import Observation

/// Nguồn sự thật **duy nhất** cho việc báo có bản app mới (dải báo ở Kệ, hàng ở Cài đặt › Thông Tin, chấm đỏ tab
/// Cài Đặt, sheet bản mới).
///
/// - Đọc `apps.json` (`AppUpdateSourceClient`) khi mở app và khi quay lại app, giãn cách 6 giờ. Bản đọc được cuối cùng
///   lưu lại ⇒ mở app lại trong 6 giờ vẫn thấy báo.
/// - Có bản mới ⇔ số build của nguồn > `CFBundleVersion` đang chạy (`AppVersionInfo.buildNumber`). Bản build tay
///   mang số build mặc định `1` ⇒ luôn thấy báo, đúng vì nó cũ hơn mọi bản CI.
/// - Trạng thái ẩn/bỏ qua/đã xem nhớ theo **số build**: bản mới hơn nữa ra là báo lại từ đầu.
///
/// Cập nhật thật làm trong LiveContainer (Sources › Refresh › Install). Link `livecontainer://install` **không** dùng
/// được từ app đang chạy bên trong LiveContainer (LiveContainer chỉ báo "mở lại LiveContainer để cài"), nên app chỉ
/// cho mở màn chính LiveContainer (`openLiveContainerURL`).
@MainActor
@Observable
final class AppUpdateRepository {
    static let shared = AppUpdateRepository()

    private static let checkInterval: TimeInterval = 6 * 60 * 60

    private enum Keys {
        static let lastCheckAt = "appUpdateLastCheckAt"
        static let latestJSON = "appUpdateLatestJSON"
        static let dismissedBuild = "appUpdateDismissedBuild"
        static let skippedBuild = "appUpdateSkippedBuild"
        static let seenBuild = "appUpdateSeenBuild"
    }

    /// Bản mới hơn bản đang chạy; `nil` ⇒ đang dùng bản mới nhất (hoặc chưa đọc được nguồn).
    private(set) var latest: AppUpdateInfo? = nil
    private var dismissedBuild = 0
    private var skippedBuild = 0
    private var seenBuild = 0
    @ObservationIgnored private var isChecking = false

    private init() {
        let defaults = UserDefaults.standard
        dismissedBuild = defaults.integer(forKey: Keys.dismissedBuild)
        skippedBuild = defaults.integer(forKey: Keys.skippedBuild)
        seenBuild = defaults.integer(forKey: Keys.seenBuild)
        if let data = defaults.data(forKey: Keys.latestJSON),
           let saved = try? JSONDecoder().decode(AppUpdateInfo.self, from: data) {
            latest = Self.newerThanRunning(saved)
        }
    }

    /// Số build đang chạy (`CFBundleVersion`); đọc không được ⇒ 0 (mọi bản trên nguồn đều tính là mới hơn).
    static var runningBuildNumber: Int {
        Int(AppVersionInfo.buildNumber ?? "") ?? 0
    }

    private static func newerThanRunning(_ info: AppUpdateInfo) -> AppUpdateInfo? {
        info.buildNumber > runningBuildNumber ? info : nil
    }

    // MARK: - Trạng thái hiển thị

    /// Bản mới chưa bị "Bỏ qua bản này".
    var pendingUpdate: AppUpdateInfo? {
        guard let latest, latest.buildNumber != skippedBuild else { return nil }
        return latest
    }

    /// Dải báo ở Kệ: có bản mới, chưa bỏ qua, chưa bấm ×.
    var showsBanner: Bool {
        guard let pending = pendingUpdate else { return false }
        return pending.buildNumber != dismissedBuild
    }

    /// Chấm đỏ tab Cài Đặt + hàng Cài đặt: có bản mới chưa bỏ qua và chưa mở sheet của bản đó.
    var showsUnseenDot: Bool {
        guard let pending = pendingUpdate else { return false }
        return pending.buildNumber != seenBuild
    }

    // MARK: - Hành động

    func dismissBanner() {
        guard let latest else { return }
        dismissedBuild = latest.buildNumber
        UserDefaults.standard.set(dismissedBuild, forKey: Keys.dismissedBuild)
    }

    func markSeen() {
        guard let latest, seenBuild != latest.buildNumber else { return }
        seenBuild = latest.buildNumber
        UserDefaults.standard.set(seenBuild, forKey: Keys.seenBuild)
    }

    func skipCurrent() {
        guard let latest else { return }
        skippedBuild = latest.buildNumber
        UserDefaults.standard.set(skippedBuild, forKey: Keys.skippedBuild)
    }

    /// Link sâu của LiveContainer chuyển về màn chính (hiện hộp xác nhận trước) — `LCShowSwitchAppConfirmation`.
    var openLiveContainerURL: URL? {
        var components = URLComponents()
        components.scheme = "livecontainer"
        components.host = "livecontainer-launch"
        components.queryItems = [URLQueryItem(name: "bundle-name", value: "ui")]
        return components.url
    }

    // MARK: - Kiểm tra

    /// Đọc nguồn nếu lần đọc trước đã quá 6 giờ. Gọi lúc mở app và khi app quay lại `.active`; gọi dồn vô hại.
    func checkIfNeeded() async {
        let defaults = UserDefaults.standard
        let lastCheck = defaults.double(forKey: Keys.lastCheckAt)
        let now = Date().timeIntervalSince1970
        guard !isChecking, now - lastCheck >= Self.checkInterval else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let info = try await AppUpdateSourceClient.fetchLatest()
            defaults.set(now, forKey: Keys.lastCheckAt)
            if let data = try? JSONEncoder().encode(info) {
                defaults.set(data, forKey: Keys.latestJSON)
            }
            latest = Self.newerThanRunning(info)
            if let latest {
                AppLogger.shared.log("⬆️ [AppUpdate] Có bản mới \(latest.display), đang dùng \(AppVersionInfo.display)")
            }
        } catch {
            AppLogger.shared.log("❌ [AppUpdate] Không đọc được nguồn cập nhật: \(error.localizedDescription)")
        }
    }
}
