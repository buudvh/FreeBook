import Foundation
import CryptoKit

/// Đường dẫn của kho dữ liệu tiện ích dạng file JSON: `applicationSupportDirectory/extension_store/`.
///
/// ```
/// extension_store/
///   installed.json            index tiện ích ĐÃ CÀI (đường dẫn tương đối)
///   repositories.json         danh sách kho
///   local_storage.json        localStorage của JS, khoá theo packageId
///   registry/<sha256>.json    cache registry từng kho
///   legacy/library-pre-ext.sqlite   bản chép library.db trước khi gỡ @Model Extension/Repository
/// ```
///
/// Script/icon **không** nằm ở đây — vẫn ở `extensions/<folder>/` (`ExtensionFolderLocator`).
/// `sha256` và `validatePathSafety` được cài riêng theo quy ước "mỗi owner tự cài" của repo.
public enum ExtensionStorePaths {
    /// Gốc thư mục dữ liệu không đổi trong một tiến trình ⇒ tính một lần.
    private static let cachedRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("extension_store", isDirectory: true)
    }()

    public static var rootURL: URL { cachedRoot }

    public static var installedURL: URL { rootURL.appendingPathComponent("installed.json") }
    public static var repositoriesURL: URL { rootURL.appendingPathComponent("repositories.json") }
    public static var localStorageURL: URL { rootURL.appendingPathComponent("local_storage.json") }
    public static var registryDirectory: URL { rootURL.appendingPathComponent("registry", isDirectory: true) }
    public static var legacyDirectory: URL { rootURL.appendingPathComponent("legacy", isDirectory: true) }
    public static var legacyDatabaseCopyURL: URL { legacyDirectory.appendingPathComponent("library-pre-ext.sqlite") }

    /// File cache registry của một kho — tên là SHA-256 hex của URL kho để mọi URL đều thành tên file an toàn.
    public static func registryURL(forRepositoryUrl url: String) -> URL {
        registryDirectory.appendingPathComponent(sha256Hex(url) + ".json")
    }

    /// Tạo gốc + `registry/` + `legacy/` nếu chưa có. Lỗi chỉ log: lần ghi sau sẽ báo lỗi cụ thể hơn.
    public static func ensureDirectories() {
        for directory in [rootURL, registryDirectory, legacyDirectory] {
            guard !FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                AppLogger.shared.log("❌ 🧩 [ExtStore] Không tạo được thư mục \(directory.lastPathComponent): \(error.localizedDescription)")
            }
        }
    }

    /// Đường dẫn phải nằm **trong** gốc `extension_store/` (sau khi chuẩn hoá `.`/`..`).
    public static func validatePathSafety(_ url: URL) -> Bool {
        let root = rootURL.standardizedFileURL.path
        let target = url.standardizedFileURL.path
        return target.hasPrefix(root + "/")
    }

    private static func sha256Hex(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
