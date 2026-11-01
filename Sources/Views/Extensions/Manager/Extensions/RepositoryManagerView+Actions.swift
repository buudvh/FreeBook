import SwiftUI

extension RepositoryManagerView {
    /// Lỗi của một lượt cài/cập nhật (`installExtensionAsync`) — "Cập nhật tất cả" gom lại để báo một lần.
    struct InstallFailure: Sendable {
        let name: String
        /// Câu báo lỗi đầy đủ, đã gán vào `errorMessage`.
        let message: String
        /// Gói dùng định dạng mã hoá mới mà app chưa đọc được (`ExtensionScriptDecoder.isUnsupportedFormat`).
        let isUnsupportedFormat: Bool
        /// Lỗi xảy ra trước khi thư mục cài bị đụng tới và máy đang có bản cài ⇒ bản đó còn nguyên.
        let keptInstalledCopy: Bool

        /// Lỗi tải/giải nén/giải mã: `ExtensionPackageInstaller` chỉ thay thư mục cài khi mọi bước đã xong.
        static func installFailed(name: String, error: Error, hadInstalledCopy: Bool) -> InstallFailure {
            let isUnsupported = ExtensionScriptDecoder.isUnsupportedFormat(error)
            var message = isUnsupported
                ? "\(name) dùng định dạng mã hoá mới, FreeBook chưa đọc được."
                : "Lỗi cài đặt/cập nhật \(name): \(error.localizedDescription)"
            if hadInstalledCopy {
                if !message.hasSuffix(".") { message += "." }
                message += " Bản đang cài vẫn giữ nguyên."
            }
            return InstallFailure(name: name, message: message, isUnsupportedFormat: isUnsupported, keptInstalledCopy: hadInstalledCopy)
        }
    }

    /// Cài/cập nhật một tiện ích của kho. Thất bại ⇒ trả lỗi (câu báo đã gán vào `errorMessage`); xong ⇒ `nil`.
    @discardableResult
    internal func installExtensionAsync(_ ext: Extension) async -> InstallFailure? {
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
        // Đang cập nhật bản đã cài: bản ghi có thư mục và thư mục đó còn trên máy.
        let hadInstalledCopy = ext.isInstalled && FileManager.default.fileExists(atPath: ext.localPath)

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

            return await MainActor.run { () -> InstallFailure? in
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
                var failure: InstallFailure?
                if case .failure(let err) = result {
                    // File đã được thay ⇒ không còn "bản đang cài giữ nguyên".
                    let message = "Lỗi lưu tiện ích \(ext.name): \(err.localizedDescription)"
                    errorMessage = message
                    failure = InstallFailure(name: ext.name, message: message, isUnsupportedFormat: false, keptInstalledCopy: false)
                }
                extensionManager.loadingStates[ext.packageId] = false

                NotificationCenter.default.post(
                    name: NSNotification.Name("extensionDidUpdate"),
                    object: nil,
                    userInfo: ["packageId": ext.packageId]
                )
                return failure
            }
        } catch {
            let failure = InstallFailure.installFailed(name: ext.name, error: error, hadInstalledCopy: hadInstalledCopy)
            await MainActor.run {
                errorMessage = failure.message
                extensionManager.loadingStates[ext.packageId] = false
            }
            return failure
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
            // Mỗi lượt cài xoá `errorMessage` lúc bắt đầu ⇒ gom lỗi lại, báo một lần ở cuối.
            var failures: [InstallFailure] = []
            for ext in targets {
                if let failure = await installExtensionAsync(ext) {
                    failures.append(failure)
                }
            }
            let updatedCount = targets.count - failures.count
            let summary = failures.isEmpty ? nil : updateAllErrorMessage(failures)
            await MainActor.run {
                isUpdatingAll = false
                statusMessage = "Đã cập nhật \(updatedCount)/\(targets.count) tiện ích."
                if let summary { errorMessage = summary }
            }
        }
    }

    /// Một lỗi ⇒ giữ câu chi tiết; nhiều lỗi ⇒ chỉ liệt kê tên theo lý do cho gọn.
    private func updateAllErrorMessage(_ failures: [InstallFailure]) -> String {
        guard failures.count > 1 else { return failures.first?.message ?? "" }
        let unsupported = failures.filter(\.isUnsupportedFormat).map(\.name)
        let others = failures.filter { !$0.isUnsupportedFormat }.map(\.name)
        var parts: [String] = []
        if !unsupported.isEmpty {
            parts.append("Định dạng mã hoá mới, FreeBook chưa đọc được: \(unsupported.joined(separator: ", ")).")
        }
        if !others.isEmpty {
            parts.append("Lỗi cập nhật: \(others.joined(separator: ", ")).")
        }
        if failures.allSatisfy(\.keptInstalledCopy) {
            parts.append("Bản đang cài vẫn giữ nguyên.")
        }
        return parts.joined(separator: " ")
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
        switch ExtensionTransactionCoordinator.shared.auditInstalledExtensions() {
        case .success(let removed):
            // Audit có thể gỡ cả bản ghi nguồn Legado mất `plugin.json` ⇒ danh sách tab Legado phải đọc lại.
            if removed > 0 { LegadoSourceRepository.shared.reload() }
        case .failure(let err):
            errorMessage = "Lỗi dọn tiện ích: \(err.localizedDescription)"
        }
    }

    /// Chỉ gỡ tiện ích JavaScript — nguồn Legado có lệnh xoá riêng ở tab "Nguồn Legado".
    @MainActor
    internal func uninstallAllExtensions() {
        for ext in library.installed where !LegadoSourcePolicy.isLegado(ext) {
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
