import Foundation
import Security

/// Kho snapshot phiên Google của từng profile Chế độ AI (1.3.614) — **Keychain**, một item cho mỗi profile.
///
/// Vì sao Keychain chứ không UserDefaults: snapshot chứa cookie phiên Google (`__Secure-1PSID`…), đọc được là chiếm
/// được tài khoản. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` để không vào backup và không sang máy khác.
///
/// Mọi lỗi Keychain chỉ log `❌` và trả `nil`/bỏ qua — hỏng kho snapshot thì app vẫn chạy như 1.3.613 (một tài khoản).
enum GoogleAccountSnapshotStore {
    private static let service = "FreeBook.GoogleAccountSnapshots"
    private static let lock = NSLock()

    static func load(profileId: String) -> GoogleAccountSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        var query = baseQuery(profileId: profileId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let snapshot = try? JSONDecoder().decode(GoogleAccountSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func save(_ snapshot: GoogleAccountSnapshot) {
        guard !snapshot.isEmpty, let data = try? JSONEncoder().encode(snapshot) else { return }
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(profileId: snapshot.profileId) as CFDictionary)
        var attributes = baseQuery(profileId: snapshot.profileId)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.shared.log("❌ 🤖 [GoogleAcc] Không lưu được snapshot phiên Google (OSStatus \(status))")
        }
    }

    static func delete(profileId: String) {
        lock.lock()
        defer { lock.unlock() }
        SecItemDelete(baseQuery(profileId: profileId) as CFDictionary)
    }

    /// Profile đang có snapshot — dùng cho màn Tài khoản Google và bộ xoay tài khoản.
    static func profileIds() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else {
            return []
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    static func contains(fingerprint: String) -> Bool {
        profileIds().contains { load(profileId: $0)?.sessionFingerprint == fingerprint }
    }

    /// Đăng xuất Google ⇒ xoá mọi snapshot của đúng tài khoản đó, giữ nguyên các tài khoản khác.
    static func deleteAll(matchingFingerprint fingerprint: String) {
        let matching = profileIds().filter { load(profileId: $0)?.sessionFingerprint == fingerprint }
        for profileId in matching {
            delete(profileId: profileId)
        }
        if !matching.isEmpty {
            AppLogger.shared.log("🤖 [GoogleAcc] Đăng xuất — xoá \(matching.count) snapshot của tài khoản vừa đăng xuất")
        }
    }

    private static func baseQuery(profileId: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: profileId
        ]
    }
}
