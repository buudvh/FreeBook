import Foundation
import Security

/// Thông tin đăng nhập và header đăng nhập của nguồn Legado (spec §10.5–§10.6), lưu **Keychain**
/// (`kSecClassGenericPassword`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`), khoá theo `packageId` của nguồn.
///
/// - Không log giá trị, không vào Backup/xuất nguồn/bộ nghiệm thu.
/// - Bộ nhớ đệm có khoá để request không chạm Keychain mỗi lần.
/// - Keychain từ chối (chạy dưới LiveContainer có thể thiếu entitlement): hạ xuống **tệp được bảo vệ**
///   `LegadoLoginFallbackStore` (cùng cách `TelegramTokenStore`; ngoài Backup, không sao lưu). Đọc: Keychain trước rồi
///   tệp; ghi Keychain được thì xoá bản tệp; xoá thì xoá cả hai. Cả hai cùng hỏng ⇒ giữ **trong bộ nhớ** tới khi app
///   thoát, ghi một dòng `❌` (không kèm giá trị) và `isPersisted(sourceKey:)` trả `false` để UI báo "chưa lưu bền".
final class LegadoLoginStore: @unchecked Sendable {
    static let shared = LegadoLoginStore()

    enum Item: String {
        /// Chuỗi JSON object của thông tin đăng nhập (`source.getLoginInfo()`).
        case info
        /// Chuỗi header đăng nhập nguyên văn (`source.getLoginHeader()`).
        case header
    }

    private static let service = "com.raikiri1498.FreeBook.legadoLogin"
    private static let checkedAtPrefix = "legado.loginCheckedAt."

    private let lock = NSLock()
    /// Khoá `packageId|item`; giá trị `nil` = đã biết là không có.
    private var cache: [String: String?] = [:]
    /// Khoá `packageId|item` hiện chỉ sống trong bộ nhớ (Keychain lẫn tệp dự phòng đều từ chối).
    private var volatileAccounts: Set<String> = []
    private var reportedFailure = false

    // MARK: - Đọc / ghi

    func value(_ item: Item, sourceKey: String) -> String? {
        let packageId = Self.packageId(sourceKey)
        let cacheKey = packageId + "|" + item.rawValue
        lock.lock()
        if let cached = cache[cacheKey] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let loaded = Self.readKeychain(account: cacheKey) ?? Self.readFallback(account: cacheKey)
        lock.lock()
        if cache[cacheKey] == nil { cache[cacheKey] = .some(loaded) }
        let result = cache[cacheKey] ?? loaded
        lock.unlock()
        return result
    }

    /// `nil` hoặc chuỗi rỗng ⇒ xoá.
    func setValue(_ value: String?, item: Item, sourceKey: String) {
        let packageId = Self.packageId(sourceKey)
        let cacheKey = packageId + "|" + item.rawValue
        let normalized = (value?.isEmpty ?? true) ? nil : value
        lock.lock()
        cache[cacheKey] = .some(normalized)
        lock.unlock()
        let persisted: Bool
        if let normalized {
            let data = Data(normalized.utf8)
            if Self.writeKeychain(data, account: cacheKey) {
                LegadoLoginFallbackStore.delete(account: cacheKey)
                persisted = true
            } else {
                persisted = LegadoLoginFallbackStore.write(data, account: cacheKey)
            }
        } else {
            Self.deleteKeychain(account: cacheKey)
            LegadoLoginFallbackStore.delete(account: cacheKey)
            persisted = true
        }
        lock.lock()
        if persisted {
            volatileAccounts.remove(cacheKey)
        } else {
            volatileAccounts.insert(cacheKey)
        }
        let shouldReport = !persisted && !reportedFailure
        if shouldReport { reportedFailure = true }
        lock.unlock()
        if shouldReport {
            AppLogger.shared.log("❌ [Legado] Keychain và tệp dự phòng đều không lưu được thông tin đăng nhập — chỉ giữ trong bộ nhớ tới khi thoát app")
        }
    }

    func loginInfo(sourceKey: String) -> String? { value(.info, sourceKey: sourceKey) }
    func loginHeader(sourceKey: String) -> String? { value(.header, sourceKey: sourceKey) }

    /// Xoá thông tin + header đăng nhập + mốc kiểm tra (đăng xuất, xoá nguồn).
    func removeAll(sourceKey: String) {
        setValue(nil, item: .info, sourceKey: sourceKey)
        setValue(nil, item: .header, sourceKey: sourceKey)
        UserDefaults.standard.removeObject(forKey: Self.checkedAtPrefix + Self.packageId(sourceKey))
    }

    /// `false` khi có giá trị chỉ nằm trong bộ nhớ (Keychain lẫn tệp dự phòng đều từ chối).
    func isPersisted(sourceKey: String) -> Bool {
        let packageId = Self.packageId(sourceKey)
        lock.lock()
        defer { lock.unlock() }
        return !volatileAccounts.contains(packageId + "|" + Item.info.rawValue)
            && !volatileAccounts.contains(packageId + "|" + Item.header.rawValue)
    }

    // MARK: - Mốc "đăng nhập/kiểm tra lúc" (không phải bí mật)

    func lastCheckedAt(sourceKey: String) -> Date? {
        let seconds = UserDefaults.standard.double(forKey: Self.checkedAtPrefix + Self.packageId(sourceKey))
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    func markChecked(sourceKey: String, at date: Date = Date()) {
        UserDefaults.standard.set(date.timeIntervalSince1970, forKey: Self.checkedAtPrefix + Self.packageId(sourceKey))
    }

    // MARK: - Keychain

    static func packageId(_ sourceKey: String) -> String {
        LegadoSourceIdentity.packageId(forSourceUrl: sourceKey)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func readKeychain(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func writeKeychain(_ data: Data, account: String) -> Bool {
        let query = baseQuery(account: account)
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return true }
        if status != errSecItemNotFound {
            SecItemDelete(query as CFDictionary)
        }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    private static func deleteKeychain(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }

    /// Bản ở tệp dự phòng (chỉ có khi Keychain từng từ chối ghi).
    private static func readFallback(account: String) -> String? {
        guard let data = LegadoLoginFallbackStore.read(account: account) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
