import Foundation

/// Tìm lại thư mục của một tiện ích khi `Extension.localPath` không còn `plugin.json`.
///
/// `localPath` là đường dẫn **tuyệt đối** lưu trong `library.db`. Lỗi thật 1.3.523 (`app_logs (105)`):
/// gốc thư mục dữ liệu của app đổi (LiveContainer — vì sao đổi vẫn UNKNOWN), mọi `localPath` trỏ về gốc
/// cũ trong khi file vẫn đủ ở `extensions/<packageId>/` hiện tại ⇒ đọc chương lỗi `ExtensionManager -3`,
/// rồi `ExtensionInstallAudit` coi là mất file và gỡ hết tiện ích khỏi tab. Restore backup chữa được vì
/// `BackupExtensionInstaller` tính lại `localPath` từ thư mục thật — resolver này làm đúng việc đó.
///
/// Chỉ đọc đĩa, không ghi DB: việc ghi path mới thuộc `ExtensionTransactionCoordinator`.
public enum ExtensionPathResolver {
    /// Thư mục thay thế cho `localPath`, hoặc `nil` khi path đang lưu còn sống hay không tìm được thư mục
    /// nào. Chỉ nhận thư mục nằm trong `extensions/` hiện tại và có `plugin.json`.
    ///
    /// Thứ tự thử: (1) phần sau `/extensions/` của path cũ ghép vào gốc hiện tại — giữ đúng thư mục con
    /// khi zip bọc `plugin.json` trong một thư mục; (2) `extensions/<packageId>/`, kể cả thư mục con có
    /// `plugin.json` (cùng luật `findMainExtensionFolder` của lúc cài).
    public static func relocatedPath(for localPath: String, packageId: String) -> String? {
        if ExtensionInstallAudit.isInstalled(localPath: localPath) { return nil }
        let root = ExtensionManager.shared.extensionsDirectory.standardizedFileURL

        if let suffix = suffixAfterExtensionsRoot(localPath),
           let found = validated(root.appendingPathComponent(suffix, isDirectory: true), under: root) {
            return found
        }

        guard isSafeComponent(packageId) else { return nil }
        let folder = root.appendingPathComponent(packageId, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }
        return validated(ExtensionManager.shared.findMainExtensionFolder(at: folder), under: root)
    }

    /// Phần gốc (trước `/extensions/`) của một path tiện ích — dùng cho log so gốc cũ/gốc mới.
    public static func storageRoot(of localPath: String) -> String? {
        guard let range = localPath.range(of: "/extensions/") else { return nil }
        return String(localPath[..<range.lowerBound])
    }

    /// Lấy lần xuất hiện **đầu tiên** của `/extensions/`: thành phần này là thư mục gốc của mọi tiện ích, còn
    /// tên thư mục con của một tiện ích có thể tình cờ chứa chữ `extensions`.
    private static func suffixAfterExtensionsRoot(_ localPath: String) -> String? {
        let trimmed = localPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "/extensions/") else { return nil }
        let suffix = String(trimmed[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !suffix.isEmpty,
              suffix.split(separator: "/").allSatisfy({ isSafeComponent(String($0)) }) else { return nil }
        return suffix
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.contains("/")
    }

    private static func validated(_ candidate: URL, under root: URL) -> String? {
        let standardized = candidate.standardizedFileURL
        guard standardized.path.hasPrefix(root.path + "/") else { return nil }
        let manifest = standardized.appendingPathComponent("plugin.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
        return standardized.path
    }
}
