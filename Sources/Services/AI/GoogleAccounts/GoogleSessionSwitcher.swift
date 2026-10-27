import Foundation
import WebKit

/// Tráo phiên đăng nhập Google giữa các profile Chế độ AI (1.3.614).
///
/// **Vì sao phải tráo chứ không tách kho:** iOS chỉ có `WKWebsiteDataStore.default()` và `.nonPersistent()`
/// (`WKWebsiteDataStore(forIdentifier:)` là API macOS). Mọi provider Google của app — Chế độ AI, Gemini Web, trình duyệt
/// bypass, trình duyệt xác minh captcha — đều dùng `.default()`, nên "đổi tài khoản" = thay toàn bộ cookie `*.google.com`
/// trong kho đó bằng snapshot của profile đích. Hệ quả đã chấp nhận: cả app cùng lúc chỉ ở một tài khoản Google.
///
/// Ba điều bắt buộc, thiếu là hỏng phiên:
/// 1. **Giải phóng WKWebView ẩn trước khi tráo** — trang đang sống giữ session cũ trong tiến trình web.
/// 2. **Dump lại snapshot sau mỗi lượt thành công** — `__Secure-1PSIDTS` bị Google xoay liên tục, snapshot cũ sẽ chết.
/// 3. **Kiểm tra `isSignedIn()` sau khi tráo** — sai thì khôi phục phiên cũ và báo thất bại, không chạy ẩn danh.
///
/// Không log giá trị cookie, chỉ log tên + domain + số lượng.
@MainActor
final class GoogleSessionSwitcher {
    static let shared = GoogleSessionSwitcher()

    /// Cờ "đã gắn phiên sẵn có vào profile đang chọn" — chỉ chạy một lần sau khi nâng cấp.
    private static let migrationKey = "FreeBook_GoogleAccountMigration_V1"

    private init() {}

    private var cookieStore: WKHTTPCookieStore {
        WKWebsiteDataStore.default().httpCookieStore
    }

    // MARK: - Đọc trạng thái

    func isSignedIn() async -> Bool {
        await GeminiWebSessionController.shared.isSignedIn()
    }

    func currentCookies() async -> [HTTPCookie] {
        let all = await cookieStore.allCookies()
        return GoogleAccountSnapshot.googleCookies(of: all)
    }

    func currentFingerprint() async -> String? {
        GoogleAccountSnapshot.fingerprint(of: await currentCookies())
    }

    // MARK: - Lưu / tráo / khôi phục

    /// Lưu phiên đang có trong kho vào profile. `false` = chưa đăng nhập Google nên không có gì để lưu.
    @discardableResult
    func captureCurrent(profileId: String) async -> Bool {
        guard let snapshot = GoogleAccountSnapshot(profileId: profileId, cookies: await currentCookies()) else {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Không lưu được phiên Google: kho chưa đăng nhập")
            return false
        }
        GoogleAccountSnapshotStore.save(snapshot)
        AppLogger.shared.log("🤖 [GoogleAcc] Lưu phiên Google cho profile \(profileId.prefix(8)) (\(snapshot.cookies.count) cookie)")
        return true
    }

    /// Tráo sang phiên của `profile`. `false` = profile chưa có snapshot hoặc tráo hỏng (đã khôi phục phiên cũ).
    func apply(profile: AIProviderProfile) async -> Bool {
        guard let snapshot = GoogleAccountSnapshotStore.load(profileId: profile.id) else {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Profile \(profile.id.prefix(8)) chưa có phiên Google — không tráo được")
            return false
        }
        return await apply(snapshot: snapshot)
    }

    func apply(snapshot: GoogleAccountSnapshot) async -> Bool {
        let previous = await currentCookies()
        releaseHiddenWebViews()
        await clearGoogleCookies()
        await setCookies(snapshot.httpCookies)
        await GeminiWebClient.shared.refreshAfterLogin()
        guard await isSignedIn() else {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Tráo phiên thất bại — khôi phục phiên cũ")
            await clearGoogleCookies()
            await setCookies(previous)
            await GeminiWebClient.shared.refreshAfterLogin()
            return false
        }
        AppLogger.shared.log("🤖 [GoogleAcc] Đã tráo sang phiên của profile \(snapshot.profileId.prefix(8)) (\(snapshot.cookies.count) cookie)")
        return true
    }

    func clearGoogleCookies() async {
        for cookie in await currentCookies() {
            await cookieStore.deleteCookie(cookie)
        }
    }

    /// Khôi phục nguyên trạng danh sách cookie đã chụp — dùng khi người dùng huỷ giữa luồng đăng nhập.
    func restore(cookies: [HTTPCookie]) async {
        releaseHiddenWebViews()
        await clearGoogleCookies()
        await setCookies(cookies)
        await GeminiWebClient.shared.refreshAfterLogin()
    }

    /// Dump lại snapshot của profile đang dùng — gọi **sau lượt thành công** để bắt kịp cookie xoay.
    func refreshSnapshotIfActive() async {
        let config = AISettingsStore.shared.loadConfiguration()
        guard config.activeProfile.isGoogleAIMode,
              GoogleAccountSnapshotStore.load(profileId: config.activeProfile.id) != nil else { return }
        await captureCurrent(profileId: config.activeProfile.id)
    }

    // MARK: - Gắn phiên sẵn có

    /// Kho đang đăng nhập một tài khoản **chưa thuộc profile nào** ⇒ gắn vào profile Chế độ AI đang chọn.
    /// Chạy trước khi xoá cookie trong luồng thêm tài khoản, để không mất tài khoản đang dùng.
    func adoptCurrentSessionIfUnowned(profile: AIProviderProfile?) async {
        guard let profile, profile.isGoogleAIMode,
              GoogleAccountSnapshotStore.load(profileId: profile.id) == nil,
              let fingerprint = await currentFingerprint(),
              !GoogleAccountSnapshotStore.contains(fingerprint: fingerprint) else { return }
        if await captureCurrent(profileId: profile.id) {
            AppLogger.shared.log("🤖 [GoogleAcc] Gắn tài khoản đang đăng nhập vào profile \(profile.name)")
        }
    }

    /// Nâng cấp từ 1.3.613: phiên Google đang có chưa có snapshot nào ⇒ tự gắn vào profile Chế độ AI đang chọn.
    /// Một lần duy nhất (cờ `UserDefaults`), không đụng gì nếu chưa đăng nhập.
    func migrateIfNeeded(profile: AIProviderProfile?) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        guard let profile, profile.isGoogleAIMode else { return }
        guard GoogleAccountSnapshotStore.load(profileId: profile.id) == nil else {
            defaults.set(true, forKey: Self.migrationKey)
            return
        }
        if await captureCurrent(profileId: profile.id) {
            AppLogger.shared.log("🤖 [GoogleAcc] Nâng cấp: gắn phiên Google sẵn có vào profile \(profile.name)")
        }
        defaults.set(true, forKey: Self.migrationKey)
    }

    // MARK: - Nội bộ

    /// Bỏ WKWebView ẩn của cả hai provider Google — trang đang sống giữ session cũ trong tiến trình web, không tráo được.
    private func releaseHiddenWebViews() {
        GoogleAIModeSessionController.shared.releaseWebView()
        GeminiWebSessionController.shared.releaseWebView()
    }

    private func setCookies(_ cookies: [HTTPCookie]) async {
        for cookie in cookies {
            await cookieStore.setCookie(cookie)
        }
    }
}
