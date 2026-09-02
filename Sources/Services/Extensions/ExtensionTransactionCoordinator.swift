import Foundation
import SwiftData

@MainActor
public final class ExtensionTransactionCoordinator {
    public static let shared = ExtensionTransactionCoordinator()

    private init() {}

    public func addRepository(url: String, name: String, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        let repo = Repository(url: url, name: name)
        context.insert(repo)
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    public func deleteRepository(url: String, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        var descriptor = FetchDescriptor<Repository>(predicate: #Predicate { $0.url == url })
        descriptor.fetchLimit = 1
        if let repo = try? context.fetch(descriptor).first {
            context.delete(repo)
            do {
                try context.save()
                return .success(())
            } catch {
                return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
            }
        }
        return .success(())
    }

    public func upsertExtension(command: UpsertExtensionCommand, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        apply(command: command, in: context)

        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Áp nhiều command rồi `save()` **một lần**. Dùng cho đồng bộ cả kho: mỗi `save()` riêng lẻ
    /// vừa là một transaction vừa kéo `@Query` của View render lại, nên kho vài chục ext trả giá rất đắt.
    public func upsertExtensions(commands: [UpsertExtensionCommand], in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        guard !commands.isEmpty else { return .success(()) }
        for command in commands {
            apply(command: command, in: context)
        }

        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Phần áp field dùng chung cho cả bản đơn lẻ và bản batch — **không** `save()`.
    private func apply(command: UpsertExtensionCommand, in context: ModelContext) {
        let pkgId = command.packageId
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == pkgId })
        descriptor.fetchLimit = 1

        var repoEntity: Repository? = nil
        if let repoUrl = command.repositoryUrl, !repoUrl.isEmpty {
            var repoDesc = FetchDescriptor<Repository>(predicate: #Predicate { $0.url == repoUrl })
            repoDesc.fetchLimit = 1
            repoEntity = try? context.fetch(repoDesc).first
        }

        if let existing = try? context.fetch(descriptor).first {
            if !command.name.isEmpty { existing.name = command.name }
            if !command.author.isEmpty { existing.author = command.author }
            existing.version = command.version
            if let remote = command.remoteVersion { existing.remoteVersion = remote }
            if !command.sourceUrl.isEmpty { existing.sourceUrl = command.sourceUrl }
            if let icon = command.iconUrl { existing.iconUrl = icon }
            if let d = command.desc { existing.desc = d }
            if !command.type.isEmpty { existing.type = command.type }
            if !command.locale.isEmpty { existing.locale = command.locale }
            if !command.downloadUrl.isEmpty { existing.downloadUrl = command.downloadUrl }
            if let path = command.localPath { existing.localPath = path }
            if let cfg = command.configJson { existing.configJson = cfg }
            if let repo = repoEntity { existing.repository = repo }
        } else {
            let newExt = Extension(
                packageId: command.packageId,
                name: command.name,
                author: command.author,
                version: command.version,
                sourceUrl: command.sourceUrl,
                iconUrl: command.iconUrl,
                desc: command.desc,
                type: command.type,
                locale: command.locale,
                localPath: command.localPath ?? "",
                isEnabled: true,
                configJson: command.configJson ?? "{}",
                downloadUrl: command.downloadUrl,
                isPinned: false,
                remoteVersion: command.remoteVersion
            )
            if let repo = repoEntity { newExt.repository = repo }
            context.insert(newExt)
        }
    }

    /// Xoá bản ghi những tiện ích của kho mà registry mới **không còn liệt kê**, trừ tiện ích đã cài.
    /// Trả về số bản ghi đã xoá (0 là hợp lệ, không phải lỗi).
    ///
    /// Lọc trên RAM qua quan hệ `Repository.extensions` thay vì viết predicate đi xuyên quan hệ: một
    /// kho chỉ vài chục ext, còn predicate lồng quan hệ trên iOS 17 là đường dễ vỡ ngầm. Tiện ích
    /// import từ file zip có `repository == nil` nên không bao giờ nằm trong tập này.
    ///
    /// Chỉ xoá **bản ghi**, không đụng file: tiện ích đã cài bị loại ngay ở bộ lọc nên không có
    /// thư mục nào cần thu hồi. Xem `PruneRepositoryExtensionsCommand` cho hai lằn ranh an toàn.
    @discardableResult
    public func pruneRepositoryExtensions(
        command: PruneRepositoryExtensionsCommand,
        in context: ModelContext
    ) -> Result<Int, ExtensionTransactionError> {
        guard !command.keepPackageIds.isEmpty else { return .success(0) }

        let repoUrl = command.repositoryUrl
        var descriptor = FetchDescriptor<Repository>(predicate: #Predicate { $0.url == repoUrl })
        descriptor.fetchLimit = 1
        guard let repo = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(repoUrl))
        }

        let stale = repo.extensions.filter { ext in
            ext.localPath.isEmpty && !command.keepPackageIds.contains(ext.packageId)
        }
        guard !stale.isEmpty else { return .success(0) }

        for ext in stale {
            context.delete(ext)
        }
        do {
            try context.save()
            return .success(stale.count)
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    public func saveExtensionConfig(command: ExtensionConfigCommand, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        let packageId = command.packageId
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == packageId })
        descriptor.fetchLimit = 1
        guard let ext = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(packageId))
        }
        ext.configJson = command.configJson
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    public func updateExtensionFolder(command: UpdateExtensionFolderCommand, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        let packageId = command.packageId
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == packageId })
        descriptor.fetchLimit = 1
        guard let ext = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(packageId))
        }
        ext.localPath = command.localFolder
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Áp kế hoạch dọn của `ExtensionInstallAudit` trong **một** transaction.
    ///
    /// Trả về số hàng đã xoá. Không hỏi xác nhận: hàng bị xoá là hàng đã mất file **và** không có
    /// nguồn để tải lại, tức nó chỉ còn là một nút Tải về không chạy được.
    @discardableResult
    public func applyInstallAudit(
        plan: ExtensionInstallAudit.Plan,
        in context: ModelContext
    ) -> Result<Int, ExtensionTransactionError> {
        guard !plan.isEmpty else { return .success(0) }

        let all = (try? context.fetch(FetchDescriptor<Extension>())) ?? []
        let deleteSet = Set(plan.deletePackageIds)
        let clearSet = Set(plan.clearFolderPackageIds)
        var deleted = 0

        for ext in all {
            if deleteSet.contains(ext.packageId) {
                context.delete(ext)
                deleted += 1
            } else if clearSet.contains(ext.packageId), !ext.localPath.isEmpty {
                ext.localPath = ""
            }
        }

        guard deleted > 0 || !clearSet.isEmpty else { return .success(0) }
        do {
            try context.save()
            if deleted > 0 {
                AppLogger.shared.log("🧹 [ExtAudit] Xoá \(deleted) tiện ích mất file và không có nguồn tải lại: \(plan.deletedNames.joined(separator: ", "))")
            }
            if !clearSet.isEmpty {
                AppLogger.shared.log("🧹 [ExtAudit] Đưa \(clearSet.count) tiện ích của kho về trạng thái chưa cài (file đã mất)")
            }
            return .success(deleted)
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    /// Xoá hẳn một tiện ích khỏi DB — dùng khi gỡ tiện ích **không** có nguồn tải lại.
    public func deleteExtension(
        packageId: String,
        in context: ModelContext
    ) -> Result<Void, ExtensionTransactionError> {
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == packageId })
        descriptor.fetchLimit = 1
        guard let ext = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(packageId))
        }
        context.delete(ext)
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    public func togglePinned(packageId: String, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == packageId })
        descriptor.fetchLimit = 1
        guard let ext = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(packageId))
        }
        ext.isPinned.toggle()
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }

    public func touchRepositoryLastUpdated(url: String, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        var descriptor = FetchDescriptor<Repository>(predicate: #Predicate { $0.url == url })
        descriptor.fetchLimit = 1
        guard let repo = try? context.fetch(descriptor).first else {
            return .failure(ExtensionTransactionError.entityNotFound(url))
        }
        repo.lastUpdated = Date()
        do {
            try context.save()
            return .success(())
        } catch {
            return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
        }
    }
}
