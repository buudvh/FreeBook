import SwiftUI

extension RepositoryManagerView {
    internal func installExtensionAsync(_ ext: Extension) async {
        // Làm mới kho không còn ghi đè bản ghi đã cài, nên đường dẫn zip mới nhất nằm ở cache registry.
        let storedDownloadUrl = registryDownloadUrl(for: ext) ?? ext.downloadUrl
        let downloadUrl = storedDownloadUrl.isEmpty ? ext.sourceUrl : storedDownloadUrl
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
                // `configJson: nil` ⇒ coordinator giữ cấu hình hiện có khi cập nhật (cài mới ⇒ "{}"); ghim,
                // lần dùng, `installedAt` và localStorage cũng được giữ — `ext` chỉ là ảnh chụp, có thể đã cũ.
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
                    downloadUrl: storedDownloadUrl,
                    configJson: nil,
                    repositoryUrl: ext.repositoryUrl,
                    installOrigin: Extension.installOriginRepository
                )
                let result = ExtensionTransactionCoordinator.shared.upsertExtension(command: cmd)
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

    /// `path` của dòng registry cùng `packageId` trong cache của kho đã cài tiện ích; `nil` nếu không có.
    @MainActor
    internal func registryDownloadUrl(for ext: Extension) -> String? {
        guard let repoUrl = ext.repositoryUrl,
              let item = library.registries[repoUrl]?.items.first(where: {
                  ExtensionSyncCommandBuilder.packageId(forName: $0.name) == ext.packageId
              }),
              !item.path.isEmpty else { return nil }
        return item.path
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

    /// Gỡ = **xoá sạch**: thư mục, bản ghi (cấu hình, ghim, lần dùng) và localStorage. Tiện ích của kho vẫn
    /// hiện lại trong catalog (từ cache registry) với nút Tải về; tiện ích import zip thì mất hẳn.
    @MainActor
    internal func uninstallExtension(_ ext: Extension) {
        guard ext.isInstalled else { return }
        let name = ext.name
        switch ExtensionTransactionCoordinator.shared.uninstallExtension(packageId: ext.packageId) {
        case .success:
            AppLogger.shared.log("🧹 [ExtManager] Đã gỡ tiện ích: \(name)")
        case .failure(let err):
            errorMessage = "Lỗi gỡ tiện ích \(name): \(err.localizedDescription)"
        }
    }

    /// Xoá bản ghi đã cài mà thư mục mất `plugin.json`. Gọi khi mở màn hình quản lý.
    @MainActor
    internal func auditInstalledExtensions() {
        if case .failure(let err) = ExtensionTransactionCoordinator.shared.auditInstalledExtensions() {
            errorMessage = "Lỗi dọn tiện ích: \(err.localizedDescription)"
        }
    }

    @MainActor
    internal func uninstallAllExtensions() {
        for ext in library.installed {
            uninstallExtension(ext)
        }
    }

    /// Nhãn loại trên dòng kho — dùng chung nhóm với bộ lọc (`ExtensionFilterGroups`), không so giá trị thô.
    internal func translateType(_ type: String) -> String {
        ExtensionFilterGroups.typeGroupLabel(ExtensionFilterGroups.typeGroup(for: type))
    }

    /// Icon dự phòng (khi tiện ích chưa có ảnh) theo nhóm thể loại.
    internal func typeIcon(_ type: String) -> String {
        ExtensionFilterGroups.typeGroupSymbol(ExtensionFilterGroups.typeGroup(for: type))
    }

    /// Cờ theo nhóm ngôn ngữ (so tiền tố sau chuẩn hoá: `global` → 🇺🇸, `ja_JP` → 🇯🇵, `kr_KR` → 🇰🇷).
    internal func getFlagEmoji(_ locale: String) -> String {
        ExtensionFilterGroups.localeGroupFlag(ExtensionFilterGroups.localeGroup(for: locale))
    }
}
