import Foundation

/// Đổi qua lại giữa thư mục **tương đối** của một tiện ích (`Extension.folder`) và đường dẫn tuyệt đối.
///
/// Vì sao lưu tương đối: lỗi thật 1.3.523 — gốc thư mục dữ liệu của app đổi (LiveContainer), mọi `localPath`
/// tuyệt đối lưu trong `library.db` trỏ về gốc cũ trong khi file vẫn đủ ở `extensions/<packageId>/` hiện tại.
/// Lưu phần sau `extensions/` rồi ghép lại với gốc của **lần chạy này** thì đổi gốc không còn làm hỏng gì.
///
/// Nằm ở Models (không phụ thuộc Services) nên công thức gốc được chép lại từ
/// `ExtensionManager.extensionsDirectory` — hai chỗ phải giữ cùng công thức. Không tạo thư mục.
public enum ExtensionFolderLocator {
    /// Gốc thư mục dữ liệu không đổi trong một tiến trình ⇒ tính một lần.
    private static let cachedRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("extensions", isDirectory: true)
    }()

    /// `applicationSupportDirectory/extensions` — cùng công thức `ExtensionManager.extensionsDirectory`.
    public static var extensionsRoot: URL { cachedRoot }

    /// Đường dẫn tuyệt đối của một thư mục tương đối; `folder` rỗng (mục catalog chưa cài) ⇒ `""`.
    public static func absolutePath(forFolder folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: Self.trimSet)
        guard !trimmed.isEmpty else { return "" }
        return extensionsRoot.appendingPathComponent(trimmed, isDirectory: true).path
    }

    /// Thư mục tương đối (dưới `extensionsRoot`) cho một đường dẫn tuyệt đối, hoặc `nil` khi không tìm được
    /// thư mục nào có `plugin.json`.
    ///
    /// Thứ tự thử: (1) phần sau lần xuất hiện **đầu tiên** của `/extensions/` — giữ đúng thư mục con khi zip
    /// bọc `plugin.json` trong một thư mục (`twkan/twkan`), và chịu được path trỏ về gốc cũ; (2) thư mục
    /// `extensions/<packageId>/`, kể cả một cấp thư mục con có `plugin.json` (cùng luật
    /// `ExtensionManager.findMainExtensionFolder` lúc cài).
    public static func folder(forAbsolutePath path: String, packageId: String) -> String? {
        let root = extensionsRoot.standardizedFileURL

        if let suffix = suffixAfterExtensionsRoot(path),
           hasManifest(root.appendingPathComponent(suffix, isDirectory: true), under: root) {
            return suffix
        }

        let trimmedId = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeComponent(trimmedId) else { return nil }
        let base = root.appendingPathComponent(trimmedId, isDirectory: true)
        guard isDirectory(base) else { return nil }
        if hasManifest(base, under: root) { return trimmedId }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        // Sắp tên để kết quả ổn định giữa các lần chạy (thứ tự liệt kê thư mục không được bảo đảm).
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = child.lastPathComponent
            guard isSafeComponent(name), isDirectory(child), hasManifest(child, under: root) else { continue }
            return trimmedId + "/" + name
        }
        return nil
    }

    // MARK: - Helpers

    private static let trimSet = CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)

    /// Lấy lần xuất hiện **đầu tiên** của `/extensions/`: đó là thư mục gốc của mọi tiện ích, còn tên thư mục
    /// con của một tiện ích có thể tình cờ chứa chữ `extensions`. Từ chối thành phần rỗng/`.`/`..`.
    private static func suffixAfterExtensionsRoot(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "/extensions/") else { return nil }
        let suffix = String(trimmed[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !suffix.isEmpty else { return nil }
        let components = suffix.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard components.allSatisfy(isSafeComponent) else { return nil }
        return components.joined(separator: "/")
    }

    private static func isSafeComponent(_ component: String) -> Bool {
        !component.isEmpty && component != "." && component != ".." && !component.contains("/")
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Thư mục phải nằm **trong** gốc hiện tại và có `plugin.json`.
    private static func hasManifest(_ candidate: URL, under root: URL) -> Bool {
        let standardized = candidate.standardizedFileURL
        guard standardized.path.hasPrefix(root.path + "/") else { return false }
        let manifest = standardized.appendingPathComponent("plugin.json")
        return FileManager.default.fileExists(atPath: manifest.path)
    }
}
