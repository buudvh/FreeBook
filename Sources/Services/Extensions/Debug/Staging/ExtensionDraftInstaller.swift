import Foundation

/// Cài bản nháp đã validate lên extension đang cài, cài **mới** một extension chưa có trên app, và
/// rollback (Phase 4 + Phase 5).
///
/// Đây là thao tác **duy nhất** trong cả phân hệ debug có thể làm mất dữ liệu của người dùng, nên nó
/// có ba chốt:
/// 1. **Không tự chạy.** `install`/`installNew` chỉ được gọi sau khi `ExtensionDebugInstallGate` báo
///    người dùng đã bấm đồng ý trên thiết bị. Không có auto-commit khi VS Code save.
/// 2. **Bản cũ được giữ trước khi thay.** Bản installed được chép sang `.backup/` *trước* khi thay:
///    gói một file ⇒ `.backup/<packageId>.json`, thư mục cũ ⇒ `.backup/<packageId>/`; `rollback` đưa lại đúng bản đó.
/// 3. **Thay nguyên tử.** Gói một file: gom thư mục nháp rồi ghi qua `ExtensionPackageWriter` (hàng đợi ghi gói, file tạm
///    cùng thư mục rồi thay). Thư mục cũ: `FileManager.replaceItemAt` trên cùng volume. Không có trạng thái nửa vời.
///
/// Thư mục nháp (vùng staging) **giữ dạng thư mục**. Cài đè luôn ghi theo **đúng dạng** của bản đang cài (router không
/// đổi `folder` của bản ghi ở đường này): gói một file ⇒ ghi lại file đó; bản ghi chưa chuyển (thư mục cũ) ⇒ thay thư mục.
/// Cài mới luôn ra `extensions/js/<packageId>.json`.
///
/// Ranh giới cố ý giữ: installer **chỉ đụng file**. Bản ghi `Extension` trong thư viện (`installed.json`)
/// do `ExtensionDebugCommandRouter` ghi qua `ExtensionTransactionCoordinator` — luật của repo là mọi ghi
/// thư viện tiện ích đi qua coordinator (`@MainActor`), còn `ExtensionDraftInstaller` là actor nền.
/// Với đường **cập nhật**, metadata thư viện vẫn không đổi (một bản nháp đang thử không nên đổi
/// tên/phiên bản trong thư viện); chỉ đường **cài mới** mới sinh bản ghi mới. Xem
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
            case .swapFailed(let reason): return "Không thay được gói extension: \(reason)"
            case .noBackup: return "Không có bản sao lưu để rollback"
            case .unsafePackageId: return "packageId không dùng được làm tên file"
            }
        }
    }

    public init() {}

    private static var backupRoot: URL {
        ExtensionDraftStagingStore.rootDirectory.appendingPathComponent(".backup", isDirectory: true)
    }

    /// Hai chỗ có thể của bản sao lưu: `<id>.json` (gói một file) và `<id>/` (thư mục cũ).
    private func backupLocations(packageId: String) -> (file: URL, directory: URL)? {
        guard ExtensionFolderLocator.isSafePackageId(packageId) else { return nil }
        return (
            Self.backupRoot.appendingPathComponent(packageId + "." + ExtensionFolderLocator.packageFileExtension),
            Self.backupRoot.appendingPathComponent(packageId, isDirectory: true)
        )
    }

    public func hasBackup(packageId: String) -> Bool {
        guard let locations = backupLocations(packageId: packageId) else { return false }
        return ExtensionPackageReader.isPresent(localPath: locations.file.path)
            || ExtensionPackageReader.isPresent(localPath: locations.directory.path)
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

    /// Tháo hẳn một bản **do debug cài mới**: xoá file gói rồi bỏ dấu. Bản ghi `Extension` trong
    /// thư viện do router xoá qua coordinator (ghi thư viện không thuộc tầng này).
    public func uninstallNewInstall(packageId: String) throws {
        guard let target = ExtensionFolderLocator.jsPackageURL(packageId: packageId) else {
            throw InstallError.unsafePackageId
        }
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

    /// Danh sách file **khác nhau** giữa bản nháp và bản đang cài (đọc qua `ExtensionPackageReader`, cả gói một file lẫn
    /// thư mục), để UI hiện trước khi xin xác nhận. Chỉ so phần **được gom vào gói** (`plugin.json`, `*.js`, `icon.png`):
    /// chữ so sau khi giải mã như lúc gom, icon so bytes. Chỉ trả path tương đối.
    public func changeSummary(draftDirectory: URL, installedPath: String) -> [String] {
        let draftPath = draftDirectory.path
        let draftFiles = Self.packagedFiles(localPath: draftPath)
        let installedFiles = Self.packagedFiles(localPath: installedPath)
        var lines: [String] = []
        for path in draftFiles.sorted() {
            if !installedFiles.contains(path) {
                lines.append("+ \(path)")
                continue
            }
            let left = ExtensionPackageReader.fileData(relativePath: path, localPath: draftPath)
            let right = ExtensionPackageReader.fileData(relativePath: path, localPath: installedPath)
            if Self.comparable(left, path: path) != Self.comparable(right, path: path) {
                lines.append("~ \(path)")
            }
        }
        for path in installedFiles.subtracting(draftFiles).sorted() {
            lines.append("- \(path)")
        }
        return lines
    }

    /// Toàn bộ file sẽ được gom của bản nháp dưới dạng dòng `+ path`, cho cửa xác nhận của đường **cài mới** — ở đó
    /// không có bản cũ nào để so, nên mọi file đều là file thêm.
    public func newInstallSummary(draftDirectory: URL) -> [String] {
        Self.packagedFiles(localPath: draftDirectory.path).sorted().map { "+ \($0)" }
    }

    public func install(draftDirectory: URL, installedPath: String, packageId: String) throws {
        guard ExtensionPackageReader.isPresent(localPath: draftDirectory.path) else { throw InstallError.draftMissing }
        let installedUrl = URL(fileURLWithPath: installedPath)
        switch ExtensionPackageReader.layout(localPath: installedPath) {
        case .jsBundle:
            try backup(installedUrl: installedUrl, packageId: packageId)
            try Self.writeBundle(from: draftDirectory, to: installedUrl)
        case .directory:
            try backup(installedUrl: installedUrl, packageId: packageId)
            try Self.atomicReplace(target: installedUrl, withContentsOf: draftDirectory, suffix: "incoming")
        case .legadoSource, nil:
            throw InstallError.installedMissing
        }
    }

    /// Cài **mới**: gom bản nháp thành `extensions/js/<packageId>.json` và trả path đích cho người gọi ghi vào bản ghi
    /// `Extension` của thư viện (qua `ExtensionTransactionCoordinator`).
    ///
    /// File đích có thể đã tồn tại dù app chưa có hàng nào trỏ tới nó (lần cài trước chết giữa đường, bản ghi bị xoá mà
    /// file còn lại). Trường hợp đó sao lưu bản cũ rồi ghi đè, nên vẫn rollback được; rollback của nó là *trả lại bản
    /// cũ*, không phải tháo ra.
    ///
    /// Thư mục nháp chỉ được **đọc**: `run.start` với `sourceMode: "draft"` phải còn chạy được sau khi cài, và vùng
    /// staging vẫn do `ExtensionDraftStagingStore` sở hữu (nó xoá sạch khi tắt server hoặc mở lại app).
    public func installNew(draftDirectory: URL, packageId: String) throws -> String {
        guard ExtensionPackageReader.isPresent(localPath: draftDirectory.path) else { throw InstallError.draftMissing }
        guard let destination = ExtensionFolderLocator.jsPackageURL(packageId: packageId) else {
            throw InstallError.unsafePackageId
        }
        let existed = FileManager.default.fileExists(atPath: destination.path)
        if existed { try backup(installedUrl: destination, packageId: packageId) }
        try Self.writeBundle(from: draftDirectory, to: destination)
        // Chỉ nhánh **tạo mới** mới đánh dấu: nhánh ghi đè có backup.
        if !existed { markNewInstall(packageId: packageId) }
        return destination.path
    }

    /// Sao lưu bản đang có sang `.backup/` (dạng giống bản đang có). Dùng chung cho mọi đường ghi đè, nên chỉ có
    /// **một** chỗ quyết định "bản cũ được giữ ở đâu". Bản sao lưu dạng kia (nếu còn từ lần trước) bị xoá.
    private func backup(installedUrl: URL, packageId: String) throws {
        let fileManager = FileManager.default
        guard let locations = backupLocations(packageId: packageId) else {
            throw InstallError.backupFailed("packageId không an toàn")
        }
        let isFile = ExtensionPackageReader.layout(localPath: installedUrl.path) != .directory
        do {
            try fileManager.createDirectory(at: Self.backupRoot, withIntermediateDirectories: true)
            for stale in [locations.file, locations.directory] where fileManager.fileExists(atPath: stale.path) {
                try fileManager.removeItem(at: stale)
            }
            try fileManager.copyItem(at: installedUrl, to: isFile ? locations.file : locations.directory)
        } catch {
            throw InstallError.backupFailed(error.localizedDescription)
        }
    }

    public func rollback(installedPath: String, packageId: String) throws {
        guard let locations = backupLocations(packageId: packageId) else { throw InstallError.noBackup }
        let installedUrl = URL(fileURLWithPath: installedPath)
        if FileManager.default.fileExists(atPath: locations.file.path) {
            do {
                let data = try Data(contentsOf: locations.file)
                try ExtensionPackageWriter.writePackageData(data, to: installedUrl)
            } catch {
                throw InstallError.swapFailed(error.localizedDescription)
            }
            return
        }
        guard FileManager.default.fileExists(atPath: locations.directory.path) else { throw InstallError.noBackup }
        try Self.atomicReplace(target: installedUrl, withContentsOf: locations.directory, suffix: "rollback")
    }

    /// Gom thư mục nháp rồi ghi gói qua hàng đợi ghi gói (nguyên tử, ghi đè).
    private static func writeBundle(from draftDirectory: URL, to target: URL) throws {
        do {
            let bundle = try ExtensionPackageWriter.makeBundle(fromDirectory: draftDirectory)
            try ExtensionPackageWriter.write(bundle, to: target)
        } catch {
            throw InstallError.swapFailed(error.localizedDescription)
        }
    }

    /// Copy sang thư mục tạm **cùng cha** với đích rồi `replaceItemAt`. Cùng cha là điều kiện để swap
    /// nằm trong một volume; `replaceItemAt` tự dọn thư mục tạm sau khi thay xong. Tên tạm có `.incoming-` /
    /// `.rollback-` để lượt dọn `extensions/` (`ExtensionPackageLayoutMigrator`) không xoá nhầm.
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

    /// File được gom vào gói: `plugin.json`, `*.js` (`listFiles`) và `icon.png` khi có.
    private static func packagedFiles(localPath: String) -> Set<String> {
        var files = Set(ExtensionPackageReader.listFiles(localPath: localPath))
        if ExtensionPackageReader.iconData(localPath: localPath) != nil {
            files.insert(ExtensionPackageReader.iconFileName)
        }
        return files
    }

    /// Dạng để so: icon so bytes; file chữ so sau khi giải mã như lúc gom (gói một file lưu chữ UTF-8).
    private static func comparable(_ data: Data?, path: String) -> String? {
        guard let data else { return nil }
        guard path != ExtensionPackageReader.iconFileName else { return data.sha256Hex() }
        return (try? ExtensionPackageWriter.text(from: data, relativePath: path)) ?? data.sha256Hex()
    }
}
