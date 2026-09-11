import Foundation
import Security

/// Lưu Bot Token trong Keychain, hạ xuống file được bảo vệ khi Keychain không dùng được dưới LiveContainer.
/// Không log giá trị token.
public enum TelegramTokenStore {
    private static let service = "com.raikiri1498.FreeBook.telegramBackup"
    private static let account = "botToken"
    private static let fallbackFileName = ".telegram_backup_token"

    public static func save(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        if saveToKeychain(data) {
            removeFallbackFile()
        } else {
            saveToFallbackFile(data)
        }
    }

    public static func load() -> String? {
        if let data = loadFromKeychain(), let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        guard let data = try? Data(contentsOf: fallbackFileURL),
              let value = String(data: data, encoding: .utf8), !value.isEmpty
        else { return nil }
        return value
    }

    public static var hasToken: Bool { load() != nil }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        removeFallbackFile()
    }

    private static func saveToKeychain(_ data: Data) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status != errSecSuccess {
            AppLogger.shared.log("⚠️ [Telegram] Không lưu được token vào Keychain (OSStatus \(status)), dùng file dự phòng")
        }
        return status == errSecSuccess
    }

    private static func loadFromKeychain() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { return nil }
        return item as? Data
    }

    private static var fallbackFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fallbackFileName)
    }

    private static func saveToFallbackFile(_ data: Data) {
        do {
            try data.write(to: fallbackFileURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: fallbackFileURL.path
            )
        } catch {
            AppLogger.shared.log("⚠️ [Telegram] Không lưu được token vào file dự phòng: \(error.localizedDescription)")
        }
    }

    private static func removeFallbackFile() {
        try? FileManager.default.removeItem(at: fallbackFileURL)
    }
}
