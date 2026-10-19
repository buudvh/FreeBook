import Foundation

/// Cửa ghi **duy nhất** cho tiện ích, kho và cache registry — giờ ghi vào `ExtensionLibraryRepository`
/// (file JSON dưới `extension_store/`) thay vì SwiftData, nên không còn tham số `in context:`.
///
/// Mỗi hàm sửa một bản sao danh sách rồi giao lại cho repository **một lần** (một lần publish, một lần ghi
/// file). Vẫn trả `Result<_, ExtensionTransactionError>` để View xử lý lỗi như cũ.
///
/// Luật giữ nguyên từ bản SwiftData:
/// - Cài/cập nhật: **file trước, bản ghi sau** — `upsertExtension` chỉ nhận `localPath` có `plugin.json`.
/// - Gỡ (`uninstallExtension`, `deleteRepository`): xoá file rồi xoá bản ghi + `localStorage` (xoá sạch).
@MainActor
public final class ExtensionTransactionCoordinator {
    public static let shared = ExtensionTransactionCoordinator()

    private var library: ExtensionLibraryRepository { ExtensionLibraryRepository.shared }

    private init() {}

    // MARK: - Kho

    /// Thêm kho (URL đã trim). Kho đã có ⇒ thành công, không đổi gì. Tên rỗng ⇒ dùng URL.
    public func addRepository(url: String, name: String) -> Result<Void, ExtensionTransactionError> {
        let key = Self.trimmed(url)
        guard !key.isEmpty else { return .failure(.saveFailed("URL kho rỗng")) }
        guard !library.repositories.contains(where: { $0.url == key }) else { return .success(()) }
        let displayName = Self.trimmed(name)
        var list = library.repositories
        list.append(ExtensionRepositoryRecord(url: key, name: displayName.isEmpty ? key : displayName))
        library.setRepositories(list)
        return .success(())
    }

    /// Xoá kho: gỡ file các tiện ích đã cài thuộc kho, xoá bản ghi + `localStorage` của chúng, xoá kho và
    /// cache registry. Kho không tồn tại vẫn dọn phần còn sót (thành công).
    ///
    /// Không chặn khi TTS đang dùng một tiện ích của kho — View kiểm tra trước khi gọi (như cũ).
    public func deleteRepository(url: String) -> Result<Void, ExtensionTransactionError> {
        let key = Self.trimmed(url)
        let owned = library.installed.filter { $0.repositoryUrl == key }
        if !owned.isEmpty {
            for ext in owned { removeFiles(of: ext) }
            let ids = Set(owned.map(\.packageId))
            library.setInstalled(library.installed.filter { !ids.contains($0.packageId) })
            for id in ids { ExtensionLocalStorageStore.shared.removeAll(namespace: id) }
        }
        let remaining = library.repositories.filter { $0.url != key }
        if remaining.count != library.repositories.count {
            library.setRepositories(remaining)
        }
        library.removeRegistry(url: key)
        return .success(())
    }

    /// Lưu cache registry vừa tải của một kho. `items` rỗng ⇒ bỏ qua (thành công): một lần fetch lỗi/trả file
    /// trắng không được quét sạch danh mục của kho.
    public func saveRegistry(url: String, items: [ExtensionRegistryItem]) -> Result<Void, ExtensionTransactionError> {
        let key = Self.trimmed(url)
        guard !key.isEmpty else { return .failure(.saveFailed("URL kho rỗng")) }
        guard !items.isEmpty else { return .success(()) }
        library.setRegistry(ExtensionRegistrySnapshot(url: key, fetchedAt: Date(), items: items))
        return .success(())
    }

    // MARK: - Cài / cập nhật

    public func upsertExtension(command: UpsertExtensionCommand) -> Result<Void, ExtensionTransactionError> {
        upsertExtensions(commands: [command])
    }

    /// Áp nhiều command rồi ghi **một lần**. Chỉ áp cho tiện ích **đã cài**:
    /// - command có `localPath` (tuyệt đối) ⇒ insert/update, `localPath` được đổi sang `folder` tương đối;
    /// - command không có `localPath` mà chưa có bản ghi ⇒ no-op thành công (mục catalog chưa cài không lưu).
    ///
    /// `localPath` không tìm được thư mục có `plugin.json` ⇒ command đó lỗi; các command khác vẫn được ghi,
    /// kết quả là `.failure` liệt kê tên lỗi.
    public func upsertExtensions(commands: [UpsertExtensionCommand]) -> Result<Void, ExtensionTransactionError> {
        guard !commands.isEmpty else { return .success(()) }
        var list = library.installed
        let knownRepositories = Set(library.repositories.map(\.url))
        let now = Date()
        var changed = false
        var failedNames: [String] = []

        for command in commands {
            switch apply(command, to: &list, knownRepositories: knownRepositories, now: now) {
            case .changed: changed = true
            case .unchanged: break
            case .failed(let name): failedNames.append(name)
            }
        }

        if changed { library.setInstalled(list) }
        guard failedNames.isEmpty else {
            let names = failedNames.joined(separator: ", ")
            AppLogger.shared.log("❌ 🧩 [ExtStore] Không tìm thấy thư mục cài (plugin.json) của: \(names)")
            return .failure(.saveFailed("Không tìm thấy thư mục cài của tiện ích: \(names)"))
        }
        return .success(())
    }

    private enum ApplyOutcome {
        case changed
        case unchanged
        case failed(String)
    }

    /// Luật update giữ như `apply(command:)` bản SwiftData: bỏ qua giá trị rỗng, `version` gán vô điều kiện.
    /// Giữ `pinnedAt`, `lastUsedAt`, `installedAt`, `configJson` (trừ khi command có `configJson`).
    /// `remoteVersion` của command bị bỏ qua — giờ tính từ cache registry.
    private func apply(
        _ command: UpsertExtensionCommand,
        to list: inout [Extension],
        knownRepositories: Set<String>,
        now: Date
    ) -> ApplyOutcome {
        let path = Self.trimmed(command.localPath ?? "")
        var resolvedFolder: String?
        if !path.isEmpty {
            guard let folder = ExtensionFolderLocator.folder(forAbsolutePath: path, packageId: command.packageId) else {
                return .failed(command.name.isEmpty ? command.packageId : command.name)
            }
            resolvedFolder = folder
        }
        // Như bản cũ (chỉ gắn quan hệ khi tìm thấy `Repository`): URL kho phải là kho đang có.
        let repoKey = Self.trimmed(command.repositoryUrl ?? "")
        let repositoryUrl: String? = knownRepositories.contains(repoKey) ? repoKey : nil
        let existingIndex = list.firstIndex(where: { $0.packageId == command.packageId })
        // Cờ NSFW tiện ích tự khai: `plugin.json` vừa cài (mọi đường cài: kho, zip, Debug, khôi phục) → registry
        // của kho. Không khai ⇒ giữ cờ cũ khi cập nhật. `savesHistory` là lựa chọn của người dùng: không đụng.
        let manifestNsfw = resolvedFolder.flatMap { folder in
            ExtensionManifestReader.nsfwFlag(localPath: ExtensionFolderLocator.absolutePath(forFolder: folder))
        }
        let existingRepositoryUrl = existingIndex.flatMap { list[$0].repositoryUrl }
        let declaredNsfw = manifestNsfw
            ?? registryNsfwFlag(packageId: command.packageId, repositoryUrl: repositoryUrl ?? existingRepositoryUrl)

        if let index = existingIndex {
            var ext = list[index]
            if let declaredNsfw { ext.isNsfw = declaredNsfw }
            if !command.name.isEmpty { ext.name = command.name }
            if !command.author.isEmpty { ext.author = command.author }
            ext.version = command.version
            if !command.sourceUrl.isEmpty { ext.sourceUrl = command.sourceUrl }
            if let icon = command.iconUrl { ext.iconUrl = icon }
            if let desc = command.desc { ext.desc = desc }
            if !command.type.isEmpty { ext.type = command.type }
            if !command.locale.isEmpty { ext.locale = command.locale }
            if !command.downloadUrl.isEmpty { ext.downloadUrl = command.downloadUrl }
            if let folder = resolvedFolder { ext.folder = folder }
            if let config = command.configJson { ext.configJson = config }
            if let origin = command.installOrigin { ext.installOrigin = origin }
            if let repositoryUrl { ext.repositoryUrl = repositoryUrl }
            ext.updatedAt = now
            list[index] = ext
            return .changed
        }

        guard let folder = resolvedFolder else { return .unchanged }
        list.append(Extension(
            packageId: command.packageId,
            name: command.name.isEmpty ? command.packageId : command.name,
            author: command.author,
            version: command.version,
            sourceUrl: command.sourceUrl,
            iconUrl: command.iconUrl,
            desc: command.desc,
            type: command.type.isEmpty ? ExtensionType.novel : command.type,
            locale: command.locale.isEmpty ? "vi_VN" : command.locale,
            folder: folder,
            configJson: command.configJson ?? "{}",
            downloadUrl: command.downloadUrl,
            repositoryUrl: repositoryUrl,
            installOrigin: command.installOrigin ?? Extension.installOriginRepository,
            installedAt: now,
            updatedAt: now,
            isNsfw: declaredNsfw
        ))
        return .changed
    }

    /// Cờ NSFW của dòng registry cùng `packageId` trong cache registry của kho `repositoryUrl`.
    private func registryNsfwFlag(packageId: String, repositoryUrl: String?) -> Bool? {
        guard let repositoryUrl, let snapshot = library.registries[repositoryUrl] else { return nil }
        let item = snapshot.items.first(where: { ExtensionSyncCommandBuilder.packageId(forName: $0.name) == packageId })
        return item?.isNsfw
    }

    // MARK: - Sửa một tiện ích đã cài

    /// Cập nhật **metadata** của một tiện ích đã cài — cửa duy nhất cho màn Cấu hình tiện ích tự lưu.
    ///
    /// Gán **đúng 6 trường** của command và **không** guard rỗng: người dùng xoá trắng `source` hay
    /// `description` thì phải xoá được thật (khác có chủ ý với `apply` của upsert). **Không** đụng `version`,
    /// `author`, `downloadUrl`, `folder`, `configJson`, `repositoryUrl`, `installOrigin`, ghim/lần dùng.
    @discardableResult
    public func updateExtensionMetadata(command: UpdateExtensionMetadataCommand) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: command.packageId) { ext in
            ext.name = command.name
            ext.sourceUrl = command.sourceUrl
            ext.iconUrl = command.iconUrl
            ext.desc = command.desc
            ext.type = command.type
            ext.locale = command.locale
        }
    }

    public func setInstallOrigin(packageId: String, origin: String) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: packageId) { $0.installOrigin = origin }
    }

    public func saveExtensionConfig(command: ExtensionConfigCommand) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: command.packageId) { $0.configJson = command.configJson }
    }

    /// Ghim ⇒ `pinnedAt = now` (ghim sau nằm cuối nhóm ghim); bỏ ghim ⇒ `nil`.
    public func togglePinned(packageId: String) -> Result<Void, ExtensionTransactionError> {
        let now = Date()
        return mutateInstalled(packageId: packageId) { ext in
            ext.pinnedAt = ext.pinnedAt == nil ? now : nil
        }
    }

    /// Bật/tắt "Lưu lịch sử đọc/xem" của tiện ích — ghi **ngay** vào bản ghi (`Extension.savesHistory`), không qua
    /// `configJson` (chuỗi đó bị tiêm thành biến global của JS). `nil` = về mặc định `!isNsfw`
    /// (`ExtensionHistoryPolicy`). Tắt chỉ chặn ghi mới vào Lịch sử; lịch sử cũ giữ nguyên.
    public func setSavesHistory(packageId: String, _ savesHistory: Bool?) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: packageId) { $0.savesHistory = savesHistory }
    }

    /// Người dùng đánh dấu (`true`) / bỏ đánh dấu (`false`) NSFW; `nil` = trả về nhận diện tự động.
    public func setNsfwOverride(packageId: String, _ override: Bool?) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: packageId) { $0.nsfwOverride = override }
    }

    /// Bật (`true`) / tắt (`false`) chặn quảng cáo cho webview của tiện ích; `nil` = "Dùng cài đặt chung". Ghi
    /// **ngay** vào bản ghi, không qua `configJson`. Áp từ lượt nạp trang kế tiếp (`WebContentPolicy`).
    public func setAdBlockOverride(packageId: String, _ value: Bool?) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: packageId) { $0.adBlockOverride = value }
    }

    /// Chế độ máy tính cho webview của tiện ích. Công tắc tắt phải truyền `nil` (khớp mặc định điện thoại).
    public func setDesktopModeOverride(packageId: String, _ value: Bool?) -> Result<Void, ExtensionTransactionError> {
        mutateInstalled(packageId: packageId) { $0.desktopModeOverride = value }
    }

    /// Đánh dấu vừa **duyệt chủ động** bằng nguồn này (chọn nguồn Khám phá, tìm bằng một nguồn, mở chi tiết).
    /// Ghi file gom ~3 s.
    @discardableResult
    public func markUsed(packageId: String) -> Result<Void, ExtensionTransactionError> {
        let now = Date()
        return mutateInstalled(packageId: packageId, debounced: true) { $0.lastUsedAt = now }
    }

    // MARK: - Gỡ / xoá

    /// Xoá bản ghi + `localStorage` của tiện ích — **không** xoá file (caller đã xoá, hoặc dùng
    /// `uninstallExtension`). `localStorage` được dọn kể cả khi không có bản ghi.
    public func deleteExtension(packageId: String) -> Result<Void, ExtensionTransactionError> {
        ExtensionLocalStorageStore.shared.removeAll(namespace: packageId)
        let list = library.installed
        guard list.contains(where: { $0.packageId == packageId }) else {
            return .failure(.entityNotFound(packageId))
        }
        library.setInstalled(list.filter { $0.packageId != packageId })
        return .success(())
    }

    /// Gỡ hẳn: xoá thư mục trước, rồi `deleteExtension` (bản ghi + `localStorage`). Cấu hình, ghim, lần dùng mất
    /// theo bản ghi — đúng nghĩa gỡ.
    public func uninstallExtension(packageId: String) -> Result<Void, ExtensionTransactionError> {
        guard let ext = library.installedExtension(packageId: packageId) else {
            return .failure(.entityNotFound(packageId))
        }
        removeFiles(of: ext)
        return deleteExtension(packageId: packageId)
    }

    /// Xoá bản ghi đã cài mà thư mục mất `plugin.json` (`ExtensionInstallAudit`). Trả số bản ghi đã xoá.
    ///
    /// Giữ `localStorage` của chúng: đây không phải người dùng gỡ, cài lại thì dữ liệu đăng nhập còn nguyên.
    @discardableResult
    public func auditInstalledExtensions() -> Result<Int, ExtensionTransactionError> {
        let entries = library.installed.map {
            ExtensionInstallAudit.Entry(packageId: $0.packageId, name: $0.name, localPath: $0.localPath)
        }
        let plan = ExtensionInstallAudit.plan(for: entries)
        guard !plan.isEmpty else { return .success(0) }
        let deleteSet = Set(plan.deletePackageIds)
        library.setInstalled(library.installed.filter { !deleteSet.contains($0.packageId) })
        // ❌: dữ liệu mất — phải hiện trong log kể cả khi công tắc log đang tắt.
        AppLogger.shared.log("❌ 🧹 [ExtAudit] Xoá \(plan.deletePackageIds.count) tiện ích mất plugin.json: \(plan.deletedNames.joined(separator: ", "))")
        return .success(plan.deletePackageIds.count)
    }

    // MARK: - Helpers

    private func mutateInstalled(
        packageId: String,
        debounced: Bool = false,
        _ body: (inout Extension) -> Void
    ) -> Result<Void, ExtensionTransactionError> {
        var list = library.installed
        guard let index = list.firstIndex(where: { $0.packageId == packageId }) else {
            return .failure(.entityNotFound(packageId))
        }
        body(&list[index])
        library.setInstalled(list, debounced: debounced)
        return .success(())
    }

    /// Xoá thư mục cài. Chỉ xoá khi path nằm **trong** `extensions/` — `folder` rỗng/`..` không bao giờ dẫn tới
    /// xoá nhầm thư mục khác (`URL(fileURLWithPath: "")` là thư mục làm việc hiện tại).
    private func removeFiles(of ext: Extension) {
        guard ext.isInstalled else { return }
        let path = ext.localPath
        let root = ExtensionFolderLocator.extensionsRoot.standardizedFileURL.path
        guard !path.isEmpty, URL(fileURLWithPath: path).standardizedFileURL.path.hasPrefix(root + "/") else {
            AppLogger.shared.log("❌ 🧩 [ExtStore] Từ chối xoá thư mục ngoài extensions/ của tiện ích \(ext.packageId)")
            return
        }
        ExtensionManager.shared.uninstall(localPath: path)
    }

    nonisolated private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
