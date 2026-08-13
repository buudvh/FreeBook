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

        do {
            try context.save()
            return .success(())
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

    public func deleteExtension(packageId: String, in context: ModelContext) -> Result<Void, ExtensionTransactionError> {
        var descriptor = FetchDescriptor<Extension>(predicate: #Predicate { $0.packageId == packageId })
        descriptor.fetchLimit = 1
        if let ext = try? context.fetch(descriptor).first {
            context.delete(ext)
            do {
                try context.save()
                return .success(())
            } catch {
                return .failure(ExtensionTransactionError.saveFailed(error.localizedDescription))
            }
        }
        return .success(())
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
