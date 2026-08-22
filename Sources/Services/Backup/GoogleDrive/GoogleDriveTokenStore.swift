import Foundation
import Security

/// Lưu refresh token của Google Drive. Ưu tiên Keychain (`AfterFirstUnlock` để lần chạy nền sau
/// khởi động lại vẫn đọc được); Keychain lỗi — hay gặp dưới LiveContainer — thì hạ xuống file
/// trong appSupport có `FileProtectionType.completeUntilFirstUserAuthentication`.
///
/// **Không bao giờ log giá trị token.**
public enum GoogleDriveTokenStore {
    private static let service = "com.raikiri1498.FreeBook.googleDrive"
    private static let account = "refreshToken"
    private static let fallbackFileName = ".google_drive_token"

    public static func save(refreshToken: String) {
        let trimmed = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }

        if saveToKeychain(data) {
            removeFallbackFile()
            return
        }
        saveToFallbackFile(data)
    }

    public static func loadRefreshToken() -> String? {
        if let data = loadFromKeychain(), let value = String(data: data, encoding: .utf8), !value.isEmpty {
            return value
        }
        guard let data = try? Data(contentsOf: fallbackFileURL),
              let value = String(data: data, encoding: .utf8),
              !value.isEmpty
        else { return nil }
        return value
    }

    public static var hasRefreshToken: Bool { loadRefreshToken() != nil }

    public static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        removeFallbackFile()
    }

    // MARK: - Keychain

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
            AppLogger.shared.log("⚠️ [Drive] Không lưu được token vào Keychain (OSStatus \(status)), dùng file dự phòng")
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

    // MARK: - File dự phòng

    private static var fallbackFileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fallbackFileName)
    }

    private static func saveToFallbackFile(_ data: Data) {
        let url = fallbackFileURL
        do {
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            AppLogger.shared.log("⚠️ [Drive] Không lưu được token vào file dự phòng: \(error.localizedDescription)")
        }
    }

    private static func removeFallbackFile() {
        try? FileManager.default.removeItem(at: fallbackFileURL)
    }
}
