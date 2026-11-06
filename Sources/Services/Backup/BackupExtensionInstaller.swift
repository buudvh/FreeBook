import Foundation

/// Cài lại gói tiện ích từ archive rồi dựng `UpsertExtensionCommand` cho `ExtensionTransactionCoordinator`.
///
/// Nhận cả hai dạng archive:
/// - **mới** (1.3.756): `extensions/js/<id>.json` (gói JS) / `extensions/legado/<id>.json` (nguồn Legado);
/// - **cũ**: thư mục `extensions/<id>/` — JS thì gom thư mục `plugin.json` thành gói, Legado thì lấy `source.json`.
/// Luôn cài ra bố cục mới. `extensions/common/` của archive cũ bị bỏ qua (không code nào đọc nó từ 02/07/2026).
///
/// Nguyên tắc: **giữ bản của máy**. Gói đã có chỉ bị thay khi `version` trong backup lớn hơn bản đang cài; bản backup
/// được kiểm đọc được (gói JSON hợp lệ / nguồn parse được) **trước** khi ghi đè. `localPath` của command luôn là gói thật
/// trên máy này — không dùng đường dẫn của máy tạo backup.
public enum BackupExtensionInstaller {
    public struct Outcome: Sendable {
        public var commands: [UpsertExtensionCommand] = []
        public var installedFolders = 0
        public var keptLocalFolders = 0
        public var errors: [String] = []
    }

    /// Gói của một bản ghi trong archive đã giải nén.
    private enum ArchivedPackage {
        /// File một gói (`extensions/js|legado/<id>.json`).
        case file(URL)
        /// Thư mục kiểu cũ `extensions/<id>/`.
        case directory(URL)
    }

    private enum InstallError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let message): return message
            }
        }
    }

    /// - Parameter existingVersions: packageId → version đang cài (`BackupLibraryWriter.existingExtensionVersions`).
    public static func install(
        from extractedDirectory: URL,
        records: [BackupPayload.ExtensionRecord],
        existingVersions: [String: Int]
    ) -> Outcome {
        var outcome = Outcome()

        for record in records {
            let isLegado = LegadoSourceIdentity.isLegado(type: record.type)
            let archived = archivedPackage(record.packageId, isLegado: isLegado, in: extractedDirectory)
            var packagePath = localPackagePath(packageId: record.packageId)
            let hasTarget = packagePath != nil

            // Không có gói ở cả hai phía thì bản ghi sẽ trỏ vào chỗ rỗng — bỏ qua. Archive cũ (bản SwiftData) còn chứa
            // hàng registry **chưa cài** (`localPathRelative` rỗng, không kèm thư mục): bỏ qua cả khi máy này đang cài
            // tiện ích đó, để metadata registry không đè bản ghi đang cài. Danh mục chưa cài tự có lại khi làm mới kho.
            guard archived != nil || (hasTarget && !record.localPathRelative.isEmpty) else { continue }

            let localVersion = existingVersions[record.packageId]
            var version = localVersion ?? record.version
            if let archived {
                let shouldReplace = !hasTarget || record.version > (localVersion ?? Int.min)
                if shouldReplace {
                    do {
                        packagePath = try install(archived, packageId: record.packageId, isLegado: isLegado)
                        version = record.version
                        outcome.installedFolders += 1
                    } catch {
                        outcome.errors.append("Extension \(record.packageId): \(error.localizedDescription)")
                        guard hasTarget else { continue }
                        outcome.keptLocalFolders += 1
                    }
                } else {
                    outcome.keptLocalFolders += 1
                }
            }
            guard let packagePath else { continue }

            // Nguồn Legado: bản ghi dựng từ nguồn **thật** sau bước thay (loại theo nội dung, kèm `installOrigin` riêng và
            // cờ 18+); `version` theo bản ghi backup khi bản backup thay vào, theo bản ghi máy này khi giữ bản của máy.
            if isLegado {
                if let command = LegadoSourceStore.restoreCommand(
                    location: URL(fileURLWithPath: packagePath), packageId: record.packageId, version: version
                ) {
                    outcome.commands.append(command)
                } else {
                    outcome.errors.append("Nguồn Legado \(record.name): không đọc được nguồn")
                }
                continue
            }

            outcome.commands.append(
                UpsertExtensionCommand(
                    packageId: record.packageId,
                    name: record.name,
                    author: record.author,
                    version: record.version,
                    sourceUrl: record.sourceUrl,
                    iconUrl: record.iconUrl,
                    desc: record.desc,
                    type: record.type,
                    locale: record.locale,
                    localPath: packagePath,
                    downloadUrl: record.downloadUrl,
                    configJson: record.configJson,
                    repositoryUrl: record.repositoryUrl
                )
            )
        }

        return outcome
    }

    /// Gói đang có trên máy: theo bản ghi đã cài (khi gói còn trên đĩa), không có bản ghi ⇒ dò trên đĩa theo `packageId`.
    private static func localPackagePath(packageId: String) -> String? {
        if let path = ExtensionLibraryRepository.snapshot(packageId: packageId)?.localPath,
           !path.isEmpty, ExtensionPackageReader.isPresent(localPath: path) {
            return path
        }
        return ExtensionFolderLocator.packagePath(packageId: packageId)
    }

    /// Dạng mới trước (`extensions/js|legado/<id>.json`), rồi thư mục cũ `extensions/<id>/`.
    private static func archivedPackage(_ packageId: String, isLegado: Bool, in extractedDirectory: URL) -> ArchivedPackage? {
        guard ExtensionFolderLocator.isSafePackageId(packageId) else { return nil }
        let parent = isLegado ? ExtensionFolderLocator.legadoFolderName : ExtensionFolderLocator.jsFolderName
        let file = extractedDirectory.appendingPathComponent(
            BackupPaths.extensionPackageEntry(folder: parent + "/" + packageId + "." + ExtensionFolderLocator.packageFileExtension)
        )
        if isRegularFile(file) { return .file(file) }
        let directory = extractedDirectory
            .appendingPathComponent(BackupPaths.extensionFolder(packageId: packageId), isDirectory: true)
        return isDirectory(directory) ? .directory(directory) : nil
    }

    /// Ghi gói từ archive ra bố cục mới; trả đường dẫn file đã ghi. Kiểm nội dung đọc được trước khi ghi đè.
    private static func install(_ archived: ArchivedPackage, packageId: String, isLegado: Bool) throws -> String {
        if isLegado {
            let sourceURL: URL
            switch archived {
            case .file(let url): sourceURL = url
            case .directory(let url): sourceURL = url.appendingPathComponent(ExtensionPackageReader.legadoSourceFileName)
            }
            guard let data = try? Data(contentsOf: sourceURL), (try? LegadoBookSource(data: data)) != nil else {
                throw InstallError.unreadable("nguồn Legado trong backup hỏng")
            }
            return try LegadoSourceStore.writeSource(sourceJSON: data, packageId: packageId).path
        }

        switch archived {
        case .file(let url):
            guard let target = ExtensionFolderLocator.jsPackageURL(packageId: packageId) else {
                throw ExtensionPackageWriter.WriteError.unsafePackageId(packageId)
            }
            guard let data = try? Data(contentsOf: url) else { throw InstallError.unreadable("không đọc được gói trong backup") }
            try ExtensionPackageWriter.writePackageData(data, to: target)
            return target.path
        case .directory(let url):
            let mainFolder = ExtensionPackageInstaller.findMainFolder(at: url)
            return try ExtensionPackageWriter.install(directory: mainFolder, packageId: packageId).path
        }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    private static func isRegularFile(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
    }
}
