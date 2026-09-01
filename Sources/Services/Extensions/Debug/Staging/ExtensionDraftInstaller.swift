import Foundation

/// Cài bản nháp đã validate lên extension đang cài, và rollback (Phase 4).
///
/// Đây là thao tác **duy nhất** trong cả phân hệ debug có thể làm mất dữ liệu của người dùng, nên nó
/// có ba chốt:
/// 1. **Không tự chạy.** `install` chỉ được gọi sau khi `ExtensionDebugInstallGate` báo người dùng đã
///    bấm đồng ý trên thiết bị. Không có auto-commit khi VS Code save.
/// 2. **Bản cũ được giữ trước khi thay.** Bản installed được copy sang `.backup/<packageId>/` *trước*
///    khi swap; `rollback` đưa lại đúng bản đó.
/// 3. **Swap nguyên tử.** Dùng `FileManager.replaceItemAt` trên cùng volume (cả hai đều trong
///    `applicationSupportDirectory`), nên không tồn tại trạng thái nửa vời: hoặc bản cũ, hoặc bản mới.
///
/// Giới hạn đã biết: installer **chỉ đổi file**. Hàng `Extension` trong SwiftData (`version`, `name`…)
/// không được cập nhật — ghi SwiftData phải đi qua `ExtensionTransactionCoordinator`, và một bản nháp
/// đang thử không nên đổi metadata thư viện. Xem `10_risk_report`.
public actor ExtensionDraftInstaller {
    public static let shared = ExtensionDraftInstaller()

    public enum InstallError: LocalizedError {
        case draftMissing
        case installedMissing
        case backupFailed(String)
        case swapFailed(String)
        case noBackup

        public var errorDescription: String? {
            switch self {
            case .draftMissing: return "Không tìm thấy bản nháp đã validate"
            case .installedMissing: return "Không tìm thấy extension đang cài"
            case .backupFailed(let reason): return "Không sao lưu được bản cũ: \(reason)"
            case .swapFailed(let reason): return "Không thay được thư mục extension: \(reason)"
            case .noBackup: return "Không có bản sao lưu để rollback"
            }
        }
    }

    public init() {}

    private static var backupRoot: URL {
        ExtensionDraftStagingStore.rootDirectory.appendingPathComponent(".backup", isDirectory: true)
    }

    public func backupDirectory(packageId: String) -> URL? {
        guard ExtensionDraftManifest.pathIssue(packageId) == nil else { return nil }
        return Self.backupRoot.appendingPathComponent(packageId, isDirectory: true)
    }

    public func hasBackup(packageId: String) -> Bool {
        guard let directory = backupDirectory(packageId: packageId) else { return false }
        return FileManager.default.fileExists(atPath: directory.appendingPathComponent("plugin.json").path)
    }

    /// Danh sách file **khác nhau** giữa bản nháp và bản đang cài, để UI hiện trước khi xin xác nhận.
    /// So bằng SHA-256 nội dung; chỉ trả path tương đối.
    public func changeSummary(draftDirectory: URL, installedPath: String) -> [String] {
        let installedUrl = URL(fileURLWithPath: installedPath)
        let draftFiles = Self.relativeFiles(in: draftDirectory)
        let installedFiles = Self.relativeFiles(in: installedUrl)
        var lines: [String] = []
        for path in draftFiles.sorted() {
            if !installedFiles.contains(path) {
                lines.append("+ \(path)")
                continue
            }
            let left = try? Data(contentsOf: draftDirectory.appendingPathComponent(path))
            let right = try? Data(contentsOf: installedUrl.appendingPathComponent(path))
            if left?.sha256Hex() != right?.sha256Hex() {
                lines.append("~ \(path)")
            }
        }
        for path in installedFiles.subtracting(draftFiles).sorted() {
            lines.append("- \(path)")
        }
        return lines
    }

    public func install(draftDirectory: URL, installedPath: String, packageId: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: draftDirectory.appendingPathComponent("plugin.json").path) else {
            throw InstallError.draftMissing
        }
        let installedUrl = URL(fileURLWithPath: installedPath)
        guard fileManager.fileExists(atPath: installedUrl.path) else { throw InstallError.installedMissing }
        guard let backupUrl = backupDirectory(packageId: packageId) else {
            throw InstallError.backupFailed("packageId không an toàn")
        }

        do {
            try fileManager.createDirectory(at: Self.backupRoot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: backupUrl.path) {
                try fileManager.removeItem(at: backupUrl)
            }
            try fileManager.copyItem(at: installedUrl, to: backupUrl)
        } catch {
            throw InstallError.backupFailed(error.localizedDescription)
        }

        try Self.atomicReplace(target: installedUrl, withContentsOf: draftDirectory, suffix: "incoming")
    }

    public func rollback(installedPath: String, packageId: String) throws {
        guard let backupUrl = backupDirectory(packageId: packageId),
              FileManager.default.fileExists(atPath: backupUrl.path) else {
            throw InstallError.noBackup
        }
        let installedUrl = URL(fileURLWithPath: installedPath)
        try Self.atomicReplace(target: installedUrl, withContentsOf: backupUrl, suffix: "rollback")
    }

    /// Copy sang thư mục tạm **cùng cha** với đích rồi `replaceItemAt`. Cùng cha là điều kiện để swap
    /// nằm trong một volume; `replaceItemAt` tự dọn thư mục tạm sau khi thay xong.
    private static func atomicReplace(target: URL, withContentsOf source: URL, suffix: String) throws {
        let fileManager = FileManager.default
        let staging = target
            .deletingLastPathComponent()
            .appendingPathComponent("\(target.lastPathComponent).\(suffix)-\(UUID().uuidString)", isDirectory: true)
        do {
            if fileManager.fileExists(atPath: staging.path) {
                try fileManager.removeItem(at: staging)
            }
            try fileManager.copyItem(at: source, to: staging)
            _ = try fileManager.replaceItemAt(target, withItemAt: staging)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw InstallError.swapFailed(error.localizedDescription)
        }
    }

    private static func relativeFiles(in directory: URL) -> Set<String> {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return []
        }
        let rootPath = directory.standardizedFileURL.path
        let rootWithSlash = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        var result: Set<String> = []
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(rootWithSlash) else { continue }
            result.insert(String(path.dropFirst(rootWithSlash.count)))
        }
        return result
    }
}
