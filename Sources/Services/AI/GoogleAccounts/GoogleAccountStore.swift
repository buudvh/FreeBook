import Foundation
import Security

/// Kho tài khoản Google của từng provider Chế độ AI (1.3.616) — **Keychain**, một item cho mỗi tài khoản.
///
/// Vì sao Keychain chứ không UserDefaults: item chứa cookie phiên Google (`__Secure-1PSID`…), đọc được là chiếm được tài
/// khoản. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` để không vào backup và không sang máy khác.
///
/// Service giữ nguyên `FreeBook.GoogleAccountSnapshots` để **đọc được item của 1.3.615** (khoá là `profileId`) trong bước
/// di trú; item mới dùng khoá `accountId` (UUID) nên hai loại không đụng nhau.
///
/// Mọi lỗi Keychain chỉ log `❌` và trả `nil`/bỏ qua — hỏng kho thì app vẫn chạy như chưa có tài khoản nào.
enum GoogleAccountStore {
    private static let service = "FreeBook.GoogleAccountSnapshots"
    private static let currentKey = "FreeBook_GoogleAccounts_Current_V1"
    private static let lock = NSLock()

    // MARK: - Đọc

    /// Tài khoản của một provider, sắp theo thứ tự xoay vòng.
    static func accounts(forProfileId profileId: String) -> [GoogleAccount] {
        allAccounts()
            .filter { $0.profileId == profileId }
            .sorted { $0.order == $1.order ? $0.savedAt < $1.savedAt : $0.order < $1.order }
    }

    static func allAccounts() -> [GoogleAccount] {
        lock.lock()
        defer { lock.unlock() }
        return rawAccounts()
    }

    static func contains(fingerprint: String) -> Bool {
        allAccounts().contains { $0.sessionFingerprint == fingerprint }
    }

    static func nextOrder(forProfileId profileId: String) -> Int {
        (accounts(forProfileId: profileId).map(\.order).max() ?? -1) + 1
    }

    // MARK: - Ghi

    static func save(_ account: GoogleAccount) {
        guard !account.isEmpty, let data = try? JSONEncoder().encode(account) else { return }
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(accountId: account.id) as CFDictionary)
        var attributes = baseQuery(accountId: account.id)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Không lưu được tài khoản Google (OSStatus \(status))")
        }
    }

    static func delete(accountId: String) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(accountId: accountId) as CFDictionary)
    }

    static func deleteAll(profileId: String) {
        for account in accounts(forProfileId: profileId) {
            delete(accountId: account.id)
        }
    }

    /// Đăng xuất Google ⇒ xoá mọi tài khoản có cùng phiên, giữ nguyên các tài khoản khác.
    static func deleteAll(matchingFingerprint fingerprint: String) {
        let matching = allAccounts().filter { $0.sessionFingerprint == fingerprint }
        for account in matching {
            delete(accountId: account.id)
        }
        if !matching.isEmpty {
            AppLogger.shared.log("🤖 [GoogleAcc] Đăng xuất — xoá \(matching.count) tài khoản Google của phiên vừa đăng xuất")
        }
    }

    /// Kéo đổi thứ tự trong một provider; ghi lại `order` 0..n-1.
    static func reorder(profileId: String, fromOffsets source: IndexSet, toOffset destination: Int) {
        let list = accounts(forProfileId: profileId)
        let moving = source.filter { $0 >= 0 && $0 < list.count }.map { list[$0] }
        guard !moving.isEmpty else { return }
        var rest = list.enumerated().filter { !source.contains($0.offset) }.map(\.element)
        let removedBefore = source.filter { $0 < destination }.count
        let insertAt = min(max(0, destination - removedBefore), rest.count)
        rest.insert(contentsOf: moving, at: insertAt)
        for (index, account) in rest.enumerated() where account.order != index {
            var updated = account
            updated.order = index
            save(updated)
        }
    }

    // MARK: - Tài khoản đang dùng

    static func currentAccountId(forProfileId profileId: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: currentKey) as? [String: String])?[profileId]
    }

    static func setCurrentAccount(_ accountId: String?, forProfileId profileId: String) {
        var map = (UserDefaults.standard.dictionary(forKey: currentKey) as? [String: String]) ?? [:]
        if let accountId {
            map[profileId] = accountId
        } else {
            map.removeValue(forKey: profileId)
        }
        UserDefaults.standard.set(map, forKey: currentKey)
    }

    /// Tài khoản đang dùng của provider, khớp lại theo kho cookie nếu con trỏ cũ không còn.
    static func currentAccount(forProfileId profileId: String, fingerprint: String?) -> GoogleAccount? {
        let list = accounts(forProfileId: profileId)
        if let id = currentAccountId(forProfileId: profileId), let match = list.first(where: { $0.id == id }) {
            return match
        }
        guard let fingerprint else { return nil }
        return list.first { $0.sessionFingerprint == fingerprint }
    }

    // MARK: - Di trú từ 1.3.615 (item khoá `profileId`)

    /// Snapshot kiểu 1.3.615 — không có `id`/`label`/`order` nên không decode được thành `GoogleAccount`.
    struct LegacySnapshot: Decodable {
        var profileId: String
        var cookies: [GoogleAccount.Cookie]
        var savedAt: Date
        var sessionFingerprint: String
    }

    static func legacySnapshot(profileId: String) -> LegacySnapshot? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(accountId: profileId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(LegacySnapshot.self, from: data)
    }

    static func deleteLegacy(profileId: String) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(accountId: profileId) as CFDictionary)
    }

    // MARK: - Nội bộ

    private static func rawAccounts() -> [GoogleAccount] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [Data] else {
            return []
        }
        return items.compactMap { try? JSONDecoder().decode(GoogleAccount.self, from: $0) }
    }

    private static func baseQuery(accountId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountId
        ]
    }
}
