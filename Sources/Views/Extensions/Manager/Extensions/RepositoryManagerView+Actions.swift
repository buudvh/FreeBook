import SwiftUI

extension RepositoryManagerView {
    internal func installExtensionAsync(_ ext: Extension) async {
        let downloadUrl = ext.downloadUrl.isEmpty ? ext.sourceUrl : ext.downloadUrl
        let targetVersion = ext.remoteVersion ?? (ext.version > 0 ? ext.version : 1)
        let finalItem = ExtensionRegistryItem(
            name: ext.name,
            author: ext.author,
            path: downloadUrl,
            version: targetVersion,
            source: ext.sourceUrl,
            icon: ext.iconUrl,
            description: ext.desc,
            type: ext.type,
            locale: ext.locale
        )

        await MainActor.run {
            extensionManager.loadingStates[ext.packageId] = true
            errorMessage = ""
        }

        do {
            let localFolder = try await ExtensionManager.shared.install(item: finalItem, packageId: ext.packageId)

            var localLocale = ext.locale
            var localType = ext.type
            var localVersion = targetVersion
            var localAuthor = ext.author
            var localSource = ext.sourceUrl

            let localJsonUrl = URL(fileURLWithPath: localFolder).appendingPathComponent("plugin.json")
            if let jsonData = try? Data(contentsOf: localJsonUrl),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                let meta = json["metadata"] as? [String: Any] ?? json
                if let v = meta["source"] as? String, !v.isEmpty { localSource = v }
                if let v = meta["locale"] as? String, !v.isEmpty { localLocale = v }
                if let v = meta["type"] as? String, !v.isEmpty { localType = v }
                if let v = meta["version"] as? Int { localVersion = v }
                else if let vs = meta["version"] as? String, let vi = Int(vs) { localVersion = vi }
                if let v = meta["author"] as? String, !v.isEmpty { localAuthor = v }
            }

            await MainActor.run {
                let cmd = UpsertExtensionCommand(
                    packageId: ext.packageId,
                    name: ext.name,
                    author: localAuthor,
                    version: localVersion,
                    remoteVersion: targetVersion,
                    sourceUrl: localSource,
                    iconUrl: ext.iconUrl,
                    desc: ext.desc,
                    type: localType,
                    locale: localLocale,
                    localPath: localFolder,
                    downloadUrl: ext.downloadUrl,
                    configJson: ext.configJson,
                    repositoryUrl: ext.repository?.url
                )
                let result = ExtensionTransactionCoordinator.shared.upsertExtension(command: cmd, in: modelContext)
                if case .failure(let err) = result {
                    errorMessage = "Lỗi lưu tiện ích \(ext.name): \(err.localizedDescription)"
                }
                extensionManager.loadingStates[ext.packageId] = false

                NotificationCenter.default.post(
                    name: NSNotification.Name("extensionDidUpdate"),
                    object: nil,
                    userInfo: ["packageId": ext.packageId]
                )
            }
        } catch {
            await MainActor.run {
                errorMessage = "Lỗi cài đặt/cập nhật \(ext.name): \(error.localizedDescription)"
                extensionManager.loadingStates[ext.packageId] = false
            }
        }
    }

    internal func updateAllExtensions() {
        let targets = updatableExtensions
        guard !targets.isEmpty, !isUpdatingAll else { return }

        isUpdatingAll = true
        statusMessage = "Đang cập nhật \(targets.count) tiện ích..."

        Task {
            for ext in targets {
                await installExtensionAsync(ext)
            }
            await MainActor.run {
                isUpdatingAll = false
                statusMessage = "Đã cập nhật xong tất cả tiện ích!"
            }
        }
    }

    @MainActor
    internal func uninstallExtension(_ ext: Extension) {
        guard !ext.localPath.isEmpty else { return }
        ExtensionManager.shared.uninstall(localPath: ext.localPath)
        let cmd = UpdateExtensionFolderCommand(packageId: ext.packageId, localFolder: "")
        let result = ExtensionTransactionCoordinator.shared.updateExtensionFolder(command: cmd, in: modelContext)
        if case .failure(let err) = result {
            errorMessage = "Lỗi gỡ tiện ích \(ext.name): \(err.localizedDescription)"
        }
    }

    @MainActor
    internal func uninstallAllExtensions() {
        let installed = allExtensions.filter { !$0.localPath.isEmpty }
        for ext in installed {
            ExtensionManager.shared.uninstall(localPath: ext.localPath)
            let cmd = UpdateExtensionFolderCommand(packageId: ext.packageId, localFolder: "")
            let res = ExtensionTransactionCoordinator.shared.updateExtensionFolder(command: cmd, in: modelContext)
            if case .failure(let err) = res {
                errorMessage = "Lỗi gỡ tiện ích \(ext.name): \(err.localizedDescription)"
            }
        }
    }

    internal func translateType(_ type: String) -> String {
        switch type {
        case ExtensionType.novel: return "Truyện chữ"
        case ExtensionType.chineseNovel: return "Truyện Trung"
        case ExtensionType.tts: return "Giọng đọc (TTS)"
        case ExtensionType.legado: return "Nguồn Legado"
        default: return type.capitalized
        }
    }

    internal func getFlagEmoji(_ locale: String) -> String {
        let cleanLocale = locale.lowercased()
        if cleanLocale.contains("vi") {
            return "🇻🇳"
        } else if cleanLocale.contains("zh") || cleanLocale.contains("cn") {
            return "🇨🇳"
        } else if cleanLocale.contains("en") {
            return "🇺🇸"
        }
        return "🌐"
    }
}
