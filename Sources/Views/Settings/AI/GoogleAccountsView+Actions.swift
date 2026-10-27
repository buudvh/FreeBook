import SwiftUI

/// Hành vi của màn Tài khoản Google (1.3.616) — tách khỏi `GoogleAccountsView.swift` để file chính gọn.
///
/// Luồng thêm tài khoản, đúng thứ tự (sai thứ tự là mất phiên đang dùng):
/// 1. Kho đang đăng nhập một tài khoản **chưa có trong provider** ⇒ thêm nó vào danh sách trước.
/// 2. Chụp lại danh sách cookie hiện tại để khôi phục nếu người dùng huỷ.
/// 3. Xoá cookie Google, mở trang đăng nhập trong trình duyệt bypass (`GeminiWebLoginLauncher`).
/// 4. Đăng nhập xong ⇒ lưu thành tài khoản mới; huỷ ⇒ khôi phục nguyên trạng cookie ở bước 2.
extension GoogleAccountsView {
    func refresh() async {
        config = AISettingsStore.shared.loadConfiguration()
        await GoogleSessionSwitcher.shared.migrateIfNeeded(profile: displayProfile)
        reloadAccounts()
    }

    func reloadAccounts() {
        guard let displayProfile else {
            accounts = []
            currentAccountId = nil
            return
        }
        accounts = GoogleAccountStore.accounts(forProfileId: displayProfile.id)
        currentAccountId = GoogleAccountStore.currentAccountId(forProfileId: displayProfile.id)
    }

    /// Kéo đổi thứ tự = đổi thứ tự xoay vòng; ghi `order` mới xuống kho.
    func moveAccounts(from source: IndexSet, to destination: Int) {
        guard let displayProfile else { return }
        GoogleAccountStore.reorder(profileId: displayProfile.id, fromOffsets: source, toOffset: destination)
        reloadAccounts()
    }

    /// Chạm một dòng = tráo phiên sang tài khoản đó.
    func useAccount(_ account: GoogleAccount) {
        guard busyAccountId == nil else { return }
        busyAccountId = account.id
        errorMessage = nil
        Task {
            let ok = await GoogleSessionSwitcher.shared.apply(account: account)
            busyAccountId = nil
            if ok {
                reloadAccounts()
            } else {
                errorMessage = "Không tráo được sang \"\(account.label)\". Kiểm tra mạng rồi thử lại, hoặc đăng nhập lại tài khoản này."
            }
        }
    }

    func startAddAccount() {
        renamingAccount = nil
        draftLabel = "Tài khoản \(accounts.count + 1)"
        showingNameAlert = true
    }

    func startRename(_ account: GoogleAccount) {
        renamingAccount = account
        draftLabel = account.label
        showingNameAlert = true
    }

    func confirmName() {
        let label = draftLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalLabel = label.isEmpty ? "Tài khoản \(accounts.count + 1)" : label
        if let account = renamingAccount {
            var renamed = account
            renamed.label = finalLabel
            GoogleAccountStore.save(renamed)
            renamingAccount = nil
            reloadAccounts()
            return
        }
        renamingAccount = nil
        Task { await runLogin(label: finalLabel) }
    }

    func deleteAccount(_ account: GoogleAccount) {
        GoogleAccountStore.delete(accountId: account.id)
        if currentAccountId == account.id {
            GoogleAccountStore.setCurrentAccount(nil, forProfileId: account.profileId)
        }
        AppLogger.shared.log("🤖 [GoogleAcc] Xoá tài khoản \"\(account.label)\" khỏi provider \(account.profileId.prefix(8))")
        reloadAccounts()
    }

    private func runLogin(label: String) async {
        guard let displayProfile else { return }
        busyAccountId = "pending"
        defer { busyAccountId = nil }
        let switcher = GoogleSessionSwitcher.shared
        await switcher.adoptCurrentSessionIfUnowned(profile: displayProfile)
        reloadAccounts()

        let backup = await switcher.currentCookies()
        await switcher.clearGoogleCookies()
        GeminiWebLoginLauncher.shared.start { success in
            Task { @MainActor in
                if success {
                    await switcher.captureCurrent(profileId: displayProfile.id, label: label)
                } else {
                    AppLogger.shared.log("🤖 [GoogleAcc] Huỷ đăng nhập — khôi phục phiên Google cũ")
                    await switcher.restore(cookies: backup)
                }
                await refresh()
            }
        }
    }
}
