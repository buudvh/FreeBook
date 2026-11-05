import Foundation
import Observation

/// Nguồn sự thật **duy nhất** cho việc báo có bản app mới (dải báo ở Kệ, hàng ở Cài đặt › Thông Tin, chấm đỏ tab
/// Cài Đặt, sheet bản mới).
///
/// - Đọc `apps.json` (`AppUpdateSourceClient`) **mỗi lần mở app** (`checkOnLaunch`), khi quay lại app nếu lần trước đã
///   quá 30 phút (`checkOnForeground`), và khi bấm dòng "Phiên bản ứng dụng" ở Cài đặt (`checkNow`). Trước 1.3.732 giãn
///   cách 6 giờ cho mọi lần ⇒ bản ra ngay sau một lần kiểm phải chờ 6 giờ mới báo. Bản đọc được cuối cùng lưu lại ⇒
///   mở app lúc mất mạng vẫn thấy báo.
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

    /// Giãn cách khi quay lại app (`checkOnForeground`); mở app và kiểm tay không giãn cách.
    private static let foregroundInterval: TimeInterval = 30 * 60

    /// Kết quả một lần kiểm — dùng cho nút kiểm tay ở Cài đặt.
    enum CheckOutcome: Sendable {
        case upToDate
        case updateAvailable(AppUpdateInfo)
        case failed
    }

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
    /// Đang đọc nguồn (Cài đặt hiện vòng xoay ở dòng phiên bản khi kiểm tay).
    private(set) var isChecking = false
    @ObservationIgnored private var checkTask: Task<CheckOutcome, Never>? = nil

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

    /// Mở app: luôn kiểm (không giãn cách).
    func checkOnLaunch() async {
        _ = await runCheck()
    }

    /// Quay lại app (`scenePhase` về `.active`): kiểm nếu lần trước đã quá 30 phút.
    func checkOnForeground() async {
        let lastCheck = UserDefaults.standard.double(forKey: Keys.lastCheckAt)
        guard Date().timeIntervalSince1970 - lastCheck >= Self.foregroundInterval else { return }
        _ = await runCheck()
    }

    /// Kiểm tay (bấm dòng "Phiên bản ứng dụng"): luôn kiểm, trả kết quả để màn báo toast / mở sheet.
    func checkNow() async -> CheckOutcome {
        await runCheck()
    }

    /// Một lượt đọc nguồn; gọi dồn khi đang có lượt chạy thì chờ chung lượt đó (không đọc chồng).
    private func runCheck() async -> CheckOutcome {
        if let checkTask {
            return await checkTask.value
        }
        isChecking = true
        let task = Task { () -> CheckOutcome in
            await self.performCheck()
        }
        checkTask = task
        let outcome = await task.value
        checkTask = nil
        isChecking = false
        return outcome
    }

    private func performCheck() async -> CheckOutcome {
        do {
            let info = try await AppUpdateSourceClient.fetchLatest()
            let defaults = UserDefaults.standard
            defaults.set(Date().timeIntervalSince1970, forKey: Keys.lastCheckAt)
            if let data = try? JSONEncoder().encode(info) {
                defaults.set(data, forKey: Keys.latestJSON)
            }
            latest = Self.newerThanRunning(info)
            if let latest {
                AppLogger.shared.log("⬆️ [AppUpdate] Có bản mới \(latest.display), đang dùng \(AppVersionInfo.display)")
                return .updateAvailable(latest)
            }
            AppLogger.shared.log("✅ [AppUpdate] Đang dùng bản mới nhất \(AppVersionInfo.display) (nguồn: \(info.display))")
            return .upToDate
        } catch {
            AppLogger.shared.log("❌ [AppUpdate] Không đọc được nguồn cập nhật: \(error.localizedDescription)")
            return .failed
        }
    }
}
