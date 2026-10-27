import SwiftUI

/// Hành vi của màn Tài khoản Google (1.3.614) — tách khỏi `GoogleAccountsView.swift` để file chính gọn.
///
/// Luồng thêm/đổi tài khoản, đúng thứ tự (sai thứ tự là mất phiên đang dùng):
/// 1. Kho đang đăng nhập một tài khoản **chưa thuộc profile nào** ⇒ gắn vào profile đang chọn trước.
/// 2. Chụp lại danh sách cookie hiện tại để khôi phục nếu người dùng huỷ.
/// 3. Xoá cookie Google, mở trang đăng nhập trong trình duyệt bypass (`GeminiWebLoginLauncher`).
/// 4. Đăng nhập xong ⇒ lưu phiên vào profile đích; huỷ ⇒ khôi phục nguyên trạng cookie ở bước 2.
extension GoogleAccountsView {
    func refresh() async {
        config = AISettingsStore.shared.loadConfiguration()
        await GoogleSessionSwitcher.shared.migrateIfNeeded(profile: config.activeProfile)
        refreshSnapshotFlags()
    }

    func refreshSnapshotFlags() {
        let ids = GoogleAccountSnapshotStore.profileIds()
        snapshotProfileIds = Set(ids)
    }

    /// Kéo đổi thứ tự = đổi thứ tự xoay vòng; ghi thẳng vào cấu hình AI.
    func moveAccounts(from source: IndexSet, to destination: Int) {
        config.moveGoogleAIModeProfiles(fromOffsets: source, toOffset: destination)
        AISettingsStore.shared.saveConfiguration(config)
    }

    /// Tạo profile Chế độ AI mới rồi đăng nhập luôn — đúng luồng "thêm tài khoản" của mockup.
    func addAccount() {
        guard busyProfileId == nil else { return }
        var profile = AIProviderProfile.defaultGoogleAIMode
        profile.id = "custom_\(UUID().uuidString.prefix(8))"
        profile.name = "Chế độ AI \(accounts.count + 1)"
        profile.isCustom = true
        config.updateActiveProfile(profile)
        AISettingsStore.shared.saveConfiguration(config)
        login(profile)
    }

    func login(_ profile: AIProviderProfile) {
        guard busyProfileId == nil else { return }
        busyProfileId = profile.id
        errorMessage = nil
        Task { await runLogin(profile) }
    }

    private func runLogin(_ profile: AIProviderProfile) async {
        defer { busyProfileId = nil }
        let switcher = GoogleSessionSwitcher.shared
        await switcher.adoptCurrentSessionIfUnowned(profile: config.activeProfile)
        refreshSnapshotFlags()

        let backup = await switcher.currentCookies()
        await switcher.clearGoogleCookies()
        GeminiWebLoginLauncher.shared.start { success in
            Task { @MainActor in
                if success {
                    await switcher.captureCurrent(profileId: profile.id)
                } else {
                    AppLogger.shared.log("🤖 [GoogleAcc] Huỷ đăng nhập — khôi phục phiên Google cũ")
                    await switcher.restore(cookies: backup)
                }
                await refresh()
            }
        }
    }
}
