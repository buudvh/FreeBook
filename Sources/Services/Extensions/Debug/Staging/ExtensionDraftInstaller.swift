import Foundation

/// Cài bản nháp đã validate lên extension đang cài, cài **mới** một extension chưa có trên app, và
/// rollback (Phase 4 + Phase 5).
///
/// Đây là thao tác **duy nhất** trong cả phân hệ debug có thể làm mất dữ liệu của người dùng, nên nó
/// có ba chốt:
/// 1. **Không tự chạy.** `install`/`installNew` chỉ được gọi sau khi `ExtensionDebugInstallGate` báo
///    người dùng đã bấm đồng ý trên thiết bị. Không có auto-commit khi VS Code save.
/// 2. **Bản cũ được giữ trước khi thay.** Bản installed được copy sang `.backup/<packageId>/` *trước*
///    khi swap; `rollback` đưa lại đúng bản đó.
/// 3. **Swap nguyên tử.** Dùng `FileManager.replaceItemAt` trên cùng volume (cả hai đều trong
///    `applicationSupportDirectory`), nên không tồn tại trạng thái nửa vời: hoặc bản cũ, hoặc bản mới.
///
/// Ranh giới cố ý giữ: installer **chỉ đụng file**. Hàng `Extension` trong SwiftData do
/// `ExtensionDebugCommandRouter` ghi qua `ExtensionTransactionCoordinator` — luật của repo là mọi ghi
/// SwiftData đi qua coordinator, và `ExtensionDraftInstaller` là actor nền không được giữ
/// `ModelContext`. Với đường **cập nhật**, metadata thư viện vẫn không đổi (một bản nháp đang thử
/// không nên đổi tên/phiên bản trong thư viện); chỉ đường **cài mới** mới sinh hàng mới. Xem
/// `10_risk_report`.
public actor ExtensionDraftInstaller {
    public static let shared = ExtensionDraftInstaller()

    public enum InstallError: LocalizedError {
        case draftMissing
        case installedMissing
        case backupFailed(String)
        case swapFailed(String)
        case noBackup
        case unsafePackageId

        public var errorDescription: String? {
            switch self {
            case .draftMissing: return "Không tìm thấy bản nháp đã validate"
            case .installedMissing: return "Không tìm thấy extension đang cài"
            case .backupFailed(let reason): return "Không sao lưu được bản cũ: \(reason)"
            case .swapFailed(let reason): return "Không thay được thư mục extension: \(reason)"
            case .noBackup: return "Không có bản sao lưu để rollback"
            case .unsafePackageId: return "packageId không dùng được làm tên thư mục"
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

    /// Nơi ghi dấu "hàng này do `draft.install` **cài mới**", cùng gốc với `.backup` nên cùng vòng đời:
    /// vùng staging bị xoá sạch khi tắt server hoặc mở lại app, tức rollback là khái niệm **trong một
    /// phiên debug**, đúng như bản sao lưu.
    private static var newInstallRoot: URL {
        ExtensionDraftStagingStore.rootDirectory.appendingPathComponent(".newinstall", isDirectory: true)
    }

    private func newInstallMarker(packageId: String) -> URL? {
        guard ExtensionDraftManifest.pathIssue(packageId) == nil else { return nil }
        return Self.newInstallRoot.appendingPathComponent(packageId)
    }

    /// Đánh dấu một hàng vừa được cài mới bởi luồng debug.
    ///
    /// Đây là điều kiện **duy nhất** cho phép `draft.rollback` tháo hàng đó ra. Không được suy từ
    /// `hasBackup == false`: extension người dùng tự cài từ kho cũng không có backup, và cho client
    /// debug xoá được chúng là biến một công cụ debug thành đường xoá dữ liệu người dùng.
    public func markNewInstall(packageId: String) {
        guard let marker = newInstallMarker(packageId: packageId) else { return }
        try? FileManager.default.createDirectory(at: Self.newInstallRoot, withIntermediateDirectories: true)
        try? Data().write(to: marker)
    }

    public func isDebugNewInstall(packageId: String) -> Bool {
        guard let marker = newInstallMarker(packageId: packageId) else { return false }
        return FileManager.default.fileExists(atPath: marker.path)
    }

    /// Tháo hẳn một bản **do debug cài mới**: xoá thư mục extension rồi bỏ dấu. Hàng `Extension` trong
    /// thư viện do router xoá (ghi SwiftData không thuộc tầng này).
    public func uninstallNewInstall(packageId: String) throws {
        guard ExtensionDraftManifest.pathIssue(packageId) == nil else { throw InstallError.unsafePackageId }
        let target = ExtensionManager.shared.extensionsDirectory
            .appendingPathComponent(packageId, isDirectory: true)
        if FileManager.default.fileExists(atPath: target.path) {
            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                throw InstallError.swapFailed(error.localizedDescription)
            }
        }
        if let marker = newInstallMarker(packageId: packageId) {
            try? FileManager.default.removeItem(at: marker)
        }
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

    /// Toàn bộ file của bản nháp dưới dạng dòng `+ path`, cho cửa xác nhận của đường **cài mới** — ở đó
    /// không có bản cũ nào để so, nên mọi file đều là file thêm.
    public func newInstallSummary(draftDirectory: URL) -> [String] {
        Self.relativeFiles(in: draftDirectory).sorted().map { "+ \($0)" }
    }

    public func install(draftDirectory: URL, installedPath: String, packageId: String) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: draftDirectory.appendingPathComponent("plugin.json").path) else {
            throw InstallError.draftMissing
        }
        let installedUrl = URL(fileURLWithPath: installedPath)
        guard fileManager.fileExists(atPath: installedUrl.path) else { throw InstallError.installedMissing }

        try backup(installedUrl: installedUrl, packageId: packageId)
        try Self.atomicReplace(target: installedUrl, withContentsOf: draftDirectory, suffix: "incoming")
    }

    /// Cài **mới**: dựng `extensions/<packageId>/` từ bản nháp và trả path đích cho người gọi ghi vào
    /// hàng SwiftData.
    ///
    /// Thư mục đích có thể đã tồn tại dù app chưa có hàng nào trỏ tới nó (lần cài trước chết giữa
    /// đường, bản ghi bị xoá mà file còn lại — đúng lớp lệch mà `ExtensionInstallAudit` đi tìm). Trường
    /// hợp đó đi cùng một đường với `install`: sao lưu bản cũ rồi thay nguyên tử, nên vẫn rollback được
    /// và không bao giờ có hai bản trộn vào nhau.
    ///
    /// Thư mục nháp được **copy**, không move: `run.start` với `sourceMode: "draft"` phải còn chạy được
    /// sau khi cài, và vùng staging vẫn do `ExtensionDraftStagingStore` sở hữu (nó xoá sạch khi tắt
    /// server hoặc mở lại app).
    public func installNew(draftDirectory: URL, packageId: String) throws -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: draftDirectory.appendingPathComponent("plugin.json").path) else {
            throw InstallError.draftMissing
        }
        guard ExtensionDraftManifest.pathIssue(packageId) == nil else {
            throw InstallError.unsafePackageId
        }
        let destination = ExtensionManager.shared.extensionsDirectory
            .appendingPathComponent(packageId, isDirectory: true)

        if fileManager.fileExists(atPath: destination.path) {
            try backup(installedUrl: destination, packageId: packageId)
            try Self.atomicReplace(target: destination, withContentsOf: draftDirectory, suffix: "incoming")
            return destination.path
        }

        do {
            try fileManager.copyItem(at: draftDirectory, to: destination)
        } catch {
            throw InstallError.swapFailed(error.localizedDescription)
        }
        // Chỉ nhánh **tạo mới** mới đánh dấu: nhánh trên đã ghi đè một bản có sẵn nên nó có backup, và
        // rollback của nó là *trả lại bản cũ*, không phải tháo ra.
        markNewInstall(packageId: packageId)
        return destination.path
    }

    /// Sao lưu bản đang có sang `.backup/<packageId>/`. Dùng chung cho cả hai đường ghi đè, nên chỉ có
    /// **một** chỗ quyết định "bản cũ được giữ ở đâu".
    private func backup(installedUrl: URL, packageId: String) throws {
        let fileManager = FileManager.default
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
