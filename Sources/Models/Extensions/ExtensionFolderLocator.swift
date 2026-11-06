import Foundation

/// Đổi qua lại giữa vị trí **tương đối** của một gói tiện ích (`Extension.folder`) và đường dẫn tuyệt đối.
///
/// Bố cục dưới `extensions/` (1.3.756):
/// - tiện ích JS: **một file** `js/<packageId>.json` (`ExtensionPackageBundle`);
/// - nguồn Legado: **một file** `legado/<packageId>.json` (nguyên văn `source.json`);
/// - bố cục cũ (thư mục `<packageId>/` có `plugin.json`, có thể lồng một cấp `twkan/twkan`) vẫn đọc được: bản ghi chuyển
///   lỗi giữ nguyên dạng cũ (`ExtensionPackageLayoutMigrator`). Đọc nội dung gói qua `ExtensionPackageReader`.
///
/// Vì sao lưu tương đối: lỗi thật 1.3.523 — gốc thư mục dữ liệu của app đổi (LiveContainer), mọi `localPath`
/// tuyệt đối lưu trong `library.db` trỏ về gốc cũ trong khi file vẫn đủ ở `extensions/` hiện tại.
/// Lưu phần sau `extensions/` rồi ghép lại với gốc của **lần chạy này** thì đổi gốc không còn làm hỏng gì.
///
/// Nằm ở Models (không phụ thuộc Services) nên công thức gốc được chép lại từ
/// `ExtensionManager.extensionsDirectory` — hai chỗ phải giữ cùng công thức. Không tạo thư mục.
public enum ExtensionFolderLocator {
    /// Thư mục chứa gói tiện ích JS (`extensions/js/`).
    public static let jsFolderName = "js"
    /// Thư mục chứa nguồn Legado (`extensions/legado/`).
    public static let legadoFolderName = "legado"
    /// Đuôi file gói.
    public static let packageFileExtension = "json"

    /// Gốc thư mục dữ liệu không đổi trong một tiến trình ⇒ tính một lần.
    private static let cachedRoot: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("extensions", isDirectory: true)
    }()

    /// `applicationSupportDirectory/extensions` — cùng công thức `ExtensionManager.extensionsDirectory`.
    public static var extensionsRoot: URL { cachedRoot }
    public static var jsRoot: URL { cachedRoot.appendingPathComponent(jsFolderName, isDirectory: true) }
    public static var legadoRoot: URL { cachedRoot.appendingPathComponent(legadoFolderName, isDirectory: true) }

    /// `extensions/js/<packageId>.json`; `nil` khi `packageId` không dùng được làm tên file.
    public static func jsPackageURL(packageId: String) -> URL? {
        packageFileURL(in: jsRoot, packageId: packageId)
    }

    /// `extensions/legado/<packageId>.json`; `nil` khi `packageId` không dùng được làm tên file.
    public static func legadoPackageURL(packageId: String) -> URL? {
        packageFileURL(in: legadoRoot, packageId: packageId)
    }

    /// `packageId` làm được tên file / thư mục: không rỗng, không `.`/`..`, không `/`, không ký tự NUL, không bắt đầu
    /// bằng `.` (file ẩn).
    public static func isSafePackageId(_ packageId: String) -> Bool {
        isSafeComponent(packageId) && !packageId.hasPrefix(".") && !packageId.contains("\0")
    }

    /// `folder` có phải dạng một file của bố cục mới (`js/<id>.json`, `legado/<id>.json`) không.
    public static func isPackageFileFolder(_ folder: String) -> Bool {
        let parts = folder.trimmingCharacters(in: trimSet).split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0] == Substring(jsFolderName) || parts[0] == Substring(legadoFolderName) else {
            return false
        }
        let name = String(parts[1])
        return isSafeComponent(name) && (name as NSString).pathExtension.lowercased() == packageFileExtension
    }

    /// Đường dẫn tuyệt đối của một vị trí tương đối; `folder` rỗng (mục catalog chưa cài) ⇒ `""`.
    public static func absolutePath(forFolder folder: String) -> String {
        let trimmed = folder.trimmingCharacters(in: Self.trimSet)
        guard !trimmed.isEmpty else { return "" }
        return extensionsRoot.appendingPathComponent(trimmed, isDirectory: !isPackageFileFolder(trimmed)).path
    }

    /// Gói của `packageId` đang có trên đĩa, không qua bản ghi: `js/<id>.json` → `legado/<id>.json` → thư mục cũ
    /// `<id>/` (hoặc thư mục con một cấp có `plugin.json`). `nil` khi không có.
    public static func packagePath(packageId: String) -> String? {
        let trimmedId = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let folder = existingFolder(packageId: trimmedId, under: extensionsRoot.standardizedFileURL) else {
            return nil
        }
        return absolutePath(forFolder: folder)
    }

    /// Vị trí tương đối (dưới `extensionsRoot`) cho một đường dẫn tuyệt đối, hoặc `nil` khi không tìm được gói nào.
    ///
    /// Thứ tự thử: (1) phần sau lần xuất hiện **đầu tiên** của `/extensions/` — file gói `js/<id>.json` /
    /// `legado/<id>.json`, hoặc thư mục có `plugin.json` (giữ đúng thư mục con khi zip bọc `plugin.json` trong một thư
    /// mục, `twkan/twkan`); chịu được path trỏ về gốc cũ. (2) dự phòng theo `packageId`: file mới trước
    /// (`js/<id>.json` → `legado/<id>.json`), rồi mới tới thư mục cũ `<id>/` và một cấp thư mục con có `plugin.json`
    /// (cùng luật `ExtensionPackageInstaller.findMainFolder` lúc cài).
    public static func folder(forAbsolutePath path: String, packageId: String) -> String? {
        let root = extensionsRoot.standardizedFileURL

        if let suffix = suffixAfterExtensionsRoot(path) {
            if isPackageFileFolder(suffix), isPackageFile(root.appendingPathComponent(suffix), under: root) {
                return suffix
            }
            if !isPackageFileFolder(suffix), hasManifest(root.appendingPathComponent(suffix, isDirectory: true), under: root) {
                return suffix
            }
        }
        return existingFolder(packageId: packageId.trimmingCharacters(in: .whitespacesAndNewlines), under: root)
    }

    // MARK: - Helpers

    private static let trimSet = CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)

    private static func packageFileURL(in directory: URL, packageId: String) -> URL? {
        let trimmed = packageId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafePackageId(trimmed) else { return nil }
        return directory.appendingPathComponent(trimmed + "." + packageFileExtension, isDirectory: false)
    }

    /// Dự phòng theo `packageId`: file mới trước, rồi thư mục cũ.
    private static func existingFolder(packageId: String, under root: URL) -> String? {
        guard isSafeComponent(packageId) else { return nil }
        let fileName = packageId + "." + packageFileExtension
        for parent in [jsFolderName, legadoFolderName] {
            let relative = parent + "/" + fileName
            if isPackageFile(root.appendingPathComponent(relative), under: root) { return relative }
        }

        let base = root.appendingPathComponent(packageId, isDirectory: true)
        guard isDirectory(base) else { return nil }
        if hasManifest(base, under: root) { return packageId }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        // Sắp tên để kết quả ổn định giữa các lần chạy (thứ tự liệt kê thư mục không được bảo đảm).
        for child in children.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let name = child.lastPathComponent
            guard isSafeComponent(name), isDirectory(child), hasManifest(child, under: root) else { continue }
            return packageId + "/" + name
        }
        return nil
    }

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

    private static func isInside(_ candidate: URL, root: URL) -> Bool {
        candidate.standardizedFileURL.path.hasPrefix(root.path + "/")
    }

    /// File gói phải nằm **trong** gốc hiện tại và là file thường.
    private static func isPackageFile(_ candidate: URL, under root: URL) -> Bool {
        guard isInside(candidate, root: root) else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && !isDir.boolValue
    }

    /// Thư mục phải nằm **trong** gốc hiện tại và có `plugin.json`.
    private static func hasManifest(_ candidate: URL, under root: URL) -> Bool {
        let standardized = candidate.standardizedFileURL
        guard isInside(standardized, root: root) else { return false }
        let manifest = standardized.appendingPathComponent(ExtensionPackageBundle.manifestPath)
        return FileManager.default.fileExists(atPath: manifest.path)
    }
}
