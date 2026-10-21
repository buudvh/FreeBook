import CryptoKit
import Foundation

/// Kho **dự phòng** cho `LegadoLoginStore` khi Keychain từ chối (app chạy dưới LiveContainer có thể thiếu entitlement
/// Keychain) — cùng cách `TelegramTokenStore` hạ xuống file được bảo vệ.
///
/// - Thư mục `applicationSupport/.legado_login/` — **ngoài** `legado_state/` (Backup của FreeBook gói `legado_state/`),
///   đánh dấu `isExcludedFromBackup` (không vào bản sao lưu iCloud/máy tính).
/// - Mỗi mục một tệp `<sha256(account)>.bin` (tên tệp không lộ nguồn), bảo vệ
///   `completeUntilFirstUserAuthentication` (khớp `AfterFirstUnlockThisDeviceOnly` của Keychain).
/// - Không log giá trị; mọi thao tác tệp qua `validatePathSafety(for:)`.
enum LegadoLoginFallbackStore {
    private static let folderName = ".legado_login"

    static func read(account: String) -> Data? {
        let url = fileURL(account: account)
        guard (try? validatePathSafety(for: url)) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    /// `true` khi đã ghi được (kèm thuộc tính bảo vệ).
    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let url = fileURL(account: account)
        do {
            try validatePathSafety(for: url)
            try prepareDirectory()
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
            return true
        } catch {
            AppLogger.shared.log("❌ [Legado] Không ghi được tệp dự phòng thông tin đăng nhập: \(error.localizedDescription)")
            return false
        }
    }

    static func delete(account: String) {
        let url = fileURL(account: account)
        guard (try? validatePathSafety(for: url)) != nil,
              FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Đường dẫn

    private static func rootDirectoryURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func fileURL(account: String) -> URL {
        let digest = SHA256.hash(data: Data(account.utf8)).map { String(format: "%02x", $0) }.joined()
        return rootDirectoryURL().appendingPathComponent(digest + ".bin")
    }

    private static func prepareDirectory() throws {
        var root = rootDirectoryURL()
        try validatePathSafety(for: root)
        guard !FileManager.default.fileExists(atPath: root.path) else { return }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
    }

    private static func validatePathSafety(for targetURL: URL) throws {
        let canonicalRoot = rootDirectoryURL().standardized.resolvingSymlinksInPath()
        let canonicalTarget = targetURL.standardized.resolvingSymlinksInPath()
        guard canonicalTarget.pathComponents.starts(with: canonicalRoot.pathComponents) else {
            throw NSError(domain: "SecurityError", code: 403,
                          userInfo: [NSLocalizedDescriptionKey: "Truy cập file ngoài thư mục đăng nhập Legado bị từ chối."])
        }
    }
}
