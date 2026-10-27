import Foundation
import WebKit

/// Tráo phiên đăng nhập Google giữa các **tài khoản trong cùng một provider** Chế độ AI (1.3.616).
///
/// **Vì sao phải tráo chứ không tách kho:** iOS chỉ có `WKWebsiteDataStore.default()` và `.nonPersistent()`
/// (`WKWebsiteDataStore(forIdentifier:)` là API macOS). Mọi provider Google của app — Chế độ AI, Gemini Web, trình duyệt
/// bypass, trình duyệt xác minh captcha — đều dùng `.default()`, nên "đổi tài khoản" = thay toàn bộ cookie `*.google.com`
/// trong kho đó bằng cookie của tài khoản đích. Hệ quả đã chấp nhận: cả app cùng lúc chỉ ở một tài khoản Google.
///
/// Ba điều bắt buộc, thiếu là hỏng phiên:
/// 1. **Giải phóng WKWebView ẩn trước khi tráo** — trang đang sống giữ session cũ trong tiến trình web.
/// 2. **Dump lại tài khoản sau mỗi lượt thành công** — `__Secure-1PSIDTS` bị Google xoay liên tục, bản lưu cũ sẽ chết.
/// 3. **Kiểm tra `isSignedIn()` sau khi tráo** — sai thì khôi phục phiên cũ và báo thất bại, không chạy ẩn danh.
///
/// Không log giá trị cookie, chỉ log nhãn tài khoản + số lượng.
@MainActor
final class GoogleSessionSwitcher {
    static let shared = GoogleSessionSwitcher()

    /// Cờ di trú sang mô hình "một provider nhiều tài khoản" (1.3.616).
    private static let migrationKey = "FreeBook_GoogleAccountModel_V2"

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
        return GoogleAccount.googleCookies(of: all)
    }

    func currentFingerprint() async -> String? {
        GoogleAccount.fingerprint(of: await currentCookies())
    }

    // MARK: - Lưu / tráo / khôi phục

    /// Lưu phiên đang có trong kho thành tài khoản của provider. Cùng phiên ⇒ cập nhật cookie của tài khoản cũ (giữ id,
    /// nhãn, thứ tự). `nil` = chưa đăng nhập Google nên không có gì để lưu.
    @discardableResult
    func captureCurrent(profileId: String, label: String) async -> GoogleAccount? {
        let cookies = await currentCookies()
        guard let fingerprint = GoogleAccount.fingerprint(of: cookies) else {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Không lưu được tài khoản Google: kho chưa đăng nhập")
            return nil
        }
        if let existing = GoogleAccountStore.accounts(forProfileId: profileId).first(where: { $0.sessionFingerprint == fingerprint }),
           let refreshed = GoogleAccount(
               profileId: profileId,
               label: existing.label,
               order: existing.order,
               cookies: cookies,
               id: existing.id
           ) {
            GoogleAccountStore.save(refreshed)
            GoogleAccountStore.setCurrentAccount(refreshed.id, forProfileId: profileId)
            return refreshed
        }
        guard let account = GoogleAccount(
            profileId: profileId,
            label: label,
            order: GoogleAccountStore.nextOrder(forProfileId: profileId),
            cookies: cookies
        ) else { return nil }
        GoogleAccountStore.save(account)
        GoogleAccountStore.setCurrentAccount(account.id, forProfileId: profileId)
        AppLogger.shared.log("🤖 [GoogleAcc] Lưu tài khoản \"\(label)\" cho provider \(profileId.prefix(8)) (\(account.cookies.count) cookie)")
        return account
    }

    /// Tráo sang tài khoản `account`. `false` = tráo hỏng (đã khôi phục phiên cũ).
    func apply(account: GoogleAccount) async -> Bool {
        let previous = await currentCookies()
        let previousAccountId = GoogleAccountStore.currentAccountId(forProfileId: account.profileId)
        releaseHiddenWebViews()
        await clearGoogleCookies()
        await setCookies(account.httpCookies)
        await GeminiWebClient.shared.refreshAfterLogin()
        guard await isSignedIn() else {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Tráo sang \"\(account.label)\" thất bại — khôi phục phiên cũ")
            await clearGoogleCookies()
            await setCookies(previous)
            await GeminiWebClient.shared.refreshAfterLogin()
            GoogleAccountStore.setCurrentAccount(previousAccountId, forProfileId: account.profileId)
            return false
        }
        GoogleAccountStore.setCurrentAccount(account.id, forProfileId: account.profileId)
        AppLogger.shared.log("🤖 [GoogleAcc] Đã tráo sang tài khoản \"\(account.label)\" (\(account.cookies.count) cookie)")
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

    /// Cập nhật cookie của tài khoản **đang dùng** sau lượt thành công. Không tạo tài khoản mới: phiên lạ thì bỏ qua.
    func refreshSnapshotIfActive() async {
        let config = AISettingsStore.shared.loadConfiguration()
        guard config.activeProfile.isGoogleAIMode else { return }
        let cookies = await currentCookies()
        guard let fingerprint = GoogleAccount.fingerprint(of: cookies),
              let existing = GoogleAccountStore.accounts(forProfileId: config.activeProfile.id)
                  .first(where: { $0.sessionFingerprint == fingerprint }),
              let refreshed = GoogleAccount(
                  profileId: existing.profileId,
                  label: existing.label,
                  order: existing.order,
                  cookies: cookies,
                  id: existing.id
              ) else { return }
        GoogleAccountStore.save(refreshed)
        GoogleAccountStore.setCurrentAccount(refreshed.id, forProfileId: existing.profileId)
    }

    // MARK: - Gắn phiên sẵn có

    /// Kho đang đăng nhập một tài khoản **chưa có trong provider** ⇒ thêm thành tài khoản mới.
    /// Chạy trước khi xoá cookie trong luồng thêm tài khoản, để không mất tài khoản đang dùng.
    func adoptCurrentSessionIfUnowned(profile: AIProviderProfile?) async {
        guard let profile, profile.isGoogleAIMode,
              let fingerprint = await currentFingerprint(),
              !GoogleAccountStore.accounts(forProfileId: profile.id).contains(where: { $0.sessionFingerprint == fingerprint })
        else { return }
        let label = "Tài khoản \(GoogleAccountStore.accounts(forProfileId: profile.id).count + 1)"
        if await captureCurrent(profileId: profile.id, label: label) != nil {
            AppLogger.shared.log("🤖 [GoogleAcc] Gắn tài khoản đang đăng nhập vào provider \(profile.name)")
        }
    }

    /// Di trú sang mô hình "một provider nhiều tài khoản" (1.3.616), chạy một lần:
    /// 1. item Keychain của 1.3.615 (mỗi profile giữ một snapshot) ⇒ thành tài khoản của provider đang chọn, nhãn = tên
    ///    profile cũ; xoá item cũ sau khi ghi xong. **Không** xoá profile thừa — người dùng tự xoá.
    /// 2. chưa có tài khoản nào mà kho đang đăng nhập ⇒ thêm "Tài khoản 1".
    func migrateIfNeeded(profile: AIProviderProfile?) async {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        let config = AISettingsStore.shared.loadConfiguration()
        let target = (profile?.isGoogleAIMode == true ? profile : nil)
            ?? config.profiles.first(where: { $0.isGoogleAIMode })
        guard let target else { return }

        for legacyProfile in config.profiles where legacyProfile.isGoogleAIMode {
            guard let legacy = GoogleAccountStore.legacySnapshot(profileId: legacyProfile.id) else { continue }
            if !GoogleAccountStore.contains(fingerprint: legacy.sessionFingerprint) {
                let cookies = GoogleAccount.httpCookies(from: legacy.cookies)
                let label = legacyProfile.name
                if let account = GoogleAccount(
                    profileId: target.id,
                    label: label,
                    order: GoogleAccountStore.nextOrder(forProfileId: target.id),
                    cookies: cookies
                ) {
                    GoogleAccountStore.save(account)
                    AppLogger.shared.log("🤖 [GoogleAcc] Di trú: tài khoản \"\(label)\" từ profile cũ sang provider \(target.name)")
                }
            }
            GoogleAccountStore.deleteLegacy(profileId: legacyProfile.id)
        }

        if GoogleAccountStore.accounts(forProfileId: target.id).isEmpty {
            await adoptCurrentSessionIfUnowned(profile: target)
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
