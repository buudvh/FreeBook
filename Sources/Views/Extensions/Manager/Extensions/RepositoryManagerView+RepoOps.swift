import SwiftUI

/// Thao tác trên **kho**: thêm, làm mới, xoá, import zip.
///
/// Làm mới/thêm kho chỉ tốn **1 request registry/kho**: lưu nguyên văn registry vào cache
/// (`saveRegistry`), danh mục tiện ích chưa cài được `ExtensionLibraryRepository.catalog` dựng từ cache đó.
/// Không còn tải `plugin.json` cho từng tiện ích chưa cài, cũng không còn bước prune — bản ghi chỉ giữ
/// tiện ích đã cài, mục bị gỡ khỏi registry tự biến mất khỏi catalog.
extension RepositoryManagerView {
    @MainActor
    internal func deleteRepository(_ repo: ExtensionRepositoryRecord) {
        guard !isRefreshingAll else {
            statusMessage = "Hãy chờ cập nhật kho hoàn tất trước khi xóa."
            return
        }

        if (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget),
           let playingPackageId = TTSManager.shared.extensionInfo?.packageId,
           library.installed.contains(where: { $0.packageId == playingPackageId && $0.repositoryUrl == repo.url }) {
            statusMessage = "Không thể xóa kho đang được TTS sử dụng. Hãy dừng TTS trước."
            return
        }

        // Coordinator gỡ file + bản ghi + localStorage của các tiện ích thuộc kho, rồi xoá kho và cache registry.
        let result = ExtensionTransactionCoordinator.shared.deleteRepository(url: repo.url)
        switch result {
        case .success:
            statusMessage = "Đã xóa kho tiện ích."
        case .failure(let err):
            errorMessage = "Xóa kho thất bại: \(err.localizedDescription)"
        }
    }

    internal func installExtension(_ ext: Extension) {
        Task {
            await installExtensionAsync(ext)
        }
    }

    @MainActor
    internal func importExtensionFromZip(_ url: URL) {
        statusMessage = "Đang giải nén & import tiện ích từ file zip..."
        errorMessage = ""

        Task {
            do {
                let result = try await ExtensionManager.shared.installFromLocalZip(fileUrl: url)
                // File đã nằm trong `extensions/` ⇒ mới ghi bản ghi (file trước, bản ghi sau).
                let cmd = UpsertExtensionCommand(packageId: result.packageId, name: result.name, author: result.author, version: result.version, remoteVersion: result.version, sourceUrl: result.sourceUrl, iconUrl: result.iconUrl, desc: result.desc, type: result.type, locale: result.locale, localPath: result.mainFolderPath, downloadUrl: "", configJson: nil, repositoryUrl: nil, installOrigin: Extension.installOriginImportZip)
                switch ExtensionTransactionCoordinator.shared.upsertExtension(command: cmd) {
                case .success:
                    statusMessage = "Đã import thành công tiện ích '\(result.name)' v\(result.version)!"
                case .failure(let err):
                    errorMessage = "Lỗi lưu tiện ích import: \(err.localizedDescription)"
                }
            } catch {
                errorMessage = "Lỗi import tệp zip: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    internal func addSampleRepository() {
        addNewRepository(name: "Kho mặc định (buudvh)", url: "https://raw.githubusercontent.com/buudvh/leech_story_ext/main/plugin.json")
    }

    @MainActor
    internal func addNewRepository(name: String, url: String) {
        let trimmedUrl = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUrl.isEmpty else { return }

        if library.repositories.contains(where: { $0.url == trimmedUrl }) {
            statusMessage = "Kho tiện ích này đã được nhập trước đó!"
            return
        }

        isRefreshingAll = true
        statusMessage = "Đang tải dữ liệu kho..."

        Task {
            defer { isRefreshingAll = false }
            let items: [ExtensionRegistryItem]
            do {
                items = try await ExtensionManager.shared.fetchRegistry(from: trimmedUrl)
            } catch {
                statusMessage = "Lỗi khi tải kho truyện: \(error.localizedDescription)"
                return
            }

            let repoName = name.isEmpty ? "Kho Tiện Ích Mới" : name
            let coordinator = ExtensionTransactionCoordinator.shared
            if case .failure(let error) = coordinator.addRepository(url: trimmedUrl, name: repoName) {
                statusMessage = "Lỗi khi lưu kho truyện: \(error.localizedDescription)"
                return
            }
            switch coordinator.saveRegistry(url: trimmedUrl, items: items) {
            case .success:
                statusMessage = "Đã nhập thành công kho '\(repoName)' với \(items.count) nguồn truyện."
            case .failure(let error):
                errorMessage = "Lỗi lưu danh mục kho '\(repoName)': \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    internal func refreshAllRepositories(force: Bool = false) {
        let repos = library.repositories
        guard !repos.isEmpty else { return }
        // Lượt tự động lúc mở tab đi qua cửa cooldown; nút refresh trên toolbar thì không. Cửa đang đóng vẫn
        // tải riêng các kho **chưa có cache registry** (vừa migrate từ SwiftData — migrator không dựng cache):
        // thiếu cache thì tab "Tất cả tiện ích" không có mục chưa cài và không biết bản cập nhật.
        let isFullPass = force || RepositoryRefreshPolicy.shouldRunAutoRefresh()
        let targets = isFullPass ? repos : repos.filter { library.registries[$0.url] == nil }
        guard !targets.isEmpty else { return }
        guard !isRefreshingAll else { return }
        isRefreshingAll = true
        statusMessage = "Đang cập nhật lại các kho..."

        Task {
            let startedAt = Date()
            var updatedCount = 0
            for repo in targets {
                do {
                    let items = try await ExtensionManager.shared.fetchRegistry(from: repo.url)
                    // Registry rỗng: `saveRegistry` giữ cache cũ — không tính là đã cập nhật được kho.
                    guard !items.isEmpty else {
                        AppLogger.shared.log("⚠️ [RepoRefresh] Registry rỗng, giữ cache cũ của kho \(repo.name)")
                        continue
                    }
                    switch ExtensionTransactionCoordinator.shared.saveRegistry(url: repo.url, items: items) {
                    case .success: updatedCount += 1
                    case .failure(let err): AppLogger.shared.log("⚠️ [RepoRefresh] Lưu registry thất bại cho kho \(repo.name): \(err.localizedDescription)")
                    }
                } catch {
                    AppLogger.shared.log("⚠️ [RepoRefresh] Fetch registry failed for repo \(repo.name): \(error.localizedDescription)")
                }
            }

            // Chỉ lượt đủ mọi kho mới đóng cửa cooldown; lượt trắng (mất mạng) không được khoá 6 tiếng tiếp theo.
            if isFullPass && updatedCount > 0 {
                RepositoryRefreshPolicy.markRefreshed()
            }
            let elapsed = String(format: "%.2f", Date().timeIntervalSince(startedAt))
            AppLogger.shared.log("ℹ️ [ExtSync] Làm mới \(updatedCount)/\(targets.count) kho (1 request/kho) trong \(elapsed)s")
            statusMessage = "Đã cập nhật \(updatedCount) kho tiện ích."
            isRefreshingAll = false
        }
    }
}
