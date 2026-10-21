import Foundation

/// Cài lại file extension từ archive rồi dựng `UpsertExtensionCommand` cho `ExtensionTransactionCoordinator`.
///
/// Nguyên tắc: **giữ bản của máy**. Thư mục đã có chỉ bị thay khi `version` trong backup lớn hơn
/// bản đang cài. `localPath` của command luôn tính lại từ thư mục thật trên máy này (coordinator đổi nó sang
/// `folder` tương đối và từ chối thư mục thiếu `plugin.json`) — không dùng đường dẫn của máy tạo backup.
public enum BackupExtensionInstaller {
    public struct Outcome: Sendable {
        public var commands: [UpsertExtensionCommand] = []
        public var installedFolders = 0
        public var keptLocalFolders = 0
        public var errors: [String] = []
    }

    /// - Parameter existingVersions: packageId → version đang cài (`BackupLibraryWriter.existingExtensionVersions`).
    public static func install(
        from extractedDirectory: URL,
        records: [BackupPayload.ExtensionRecord],
        existingVersions: [String: Int]
    ) -> Outcome {
        var outcome = Outcome()
        let root = ExtensionManager.shared.extensionsDirectory

        installCommonFolder(from: extractedDirectory, root: root, into: &outcome)

        for record in records {
            let source = extractedDirectory
                .appendingPathComponent(BackupPaths.extensionFolder(packageId: record.packageId), isDirectory: true)
            let target = root.appendingPathComponent(record.packageId, isDirectory: true)

            let hasSource = isDirectory(source)
            let hasTarget = isDirectory(target)

            // Không có file ở cả hai phía thì bản ghi sẽ trỏ vào thư mục rỗng — bỏ qua. Archive cũ (bản SwiftData)
            // còn chứa hàng registry **chưa cài** (`localPathRelative` rỗng, không kèm thư mục): bỏ qua cả khi máy
            // này đang cài tiện ích đó, để metadata registry không đè bản ghi đang cài. Danh mục chưa cài tự có
            // lại khi làm mới kho.
            guard hasSource || (hasTarget && !record.localPathRelative.isEmpty) else { continue }

            if hasSource {
                let localVersion = existingVersions[record.packageId]
                let shouldReplace = !hasTarget || record.version > (localVersion ?? Int.min)
                if shouldReplace {
                    do {
                        try replace(source: source, target: target)
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

            // Nguồn Legado: bản ghi dựng từ thư mục **thật** sau bước thay (type/version theo `plugin.json`, kèm
            // `installOrigin` riêng) — không lấy metadata của archive khi máy giữ bản mới hơn.
            if LegadoSourceIdentity.isLegado(type: record.type) {
                if let command = LegadoSourceStore.restoreCommand(directory: target, packageId: record.packageId) {
                    outcome.commands.append(command)
                } else {
                    outcome.errors.append("Nguồn Legado \(record.name): thư mục thiếu source.json/plugin.json")
                }
                continue
            }

            let mainFolder = ExtensionManager.shared.findMainExtensionFolder(at: target)
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
                    localPath: mainFolder.path,
                    downloadUrl: record.downloadUrl,
                    configJson: record.configJson,
                    repositoryUrl: record.repositoryUrl
                )
            )
        }

        return outcome
    }

    /// `extensions/common` là thư mục JS dùng chung (`load(...)` của script), không thuộc packageId nào.
    /// Gộp theo từng file: chỉ thêm file máy còn thiếu, không đụng bản đang có.
    private static func installCommonFolder(from extractedDirectory: URL, root: URL, into outcome: inout Outcome) {
        let source = extractedDirectory
            .appendingPathComponent(BackupPaths.extensionCommonFolder, isDirectory: true)
        guard isDirectory(source) else { return }

        let target = root.appendingPathComponent(BackupPaths.extensionCommonFolderName, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: source.path) else { return }

        do {
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        } catch {
            outcome.errors.append("Extension common: \(error.localizedDescription)")
            return
        }

        for name in names.sorted() {
            let fileTarget = target.appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: fileTarget.path) else { continue }
            do {
                try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: fileTarget)
            } catch {
                outcome.errors.append("Extension common/\(name): \(error.localizedDescription)")
            }
        }
    }

    private static func replace(source: URL, target: URL) throws {
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: source, to: target)
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
}
