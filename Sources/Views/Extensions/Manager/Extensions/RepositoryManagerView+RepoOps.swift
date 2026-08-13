import SwiftUI

extension RepositoryManagerView {
    internal func deleteRepository(_ repo: Repository) {
        guard !isRefreshingAll else {
            statusMessage = "Hãy chờ cập nhật kho hoàn tất trước khi xóa."
            return
        }

        if (TTSManager.shared.isPlaying || TTSManager.shared.showFloatingWidget),
           let playingPackageId = TTSManager.shared.extensionInfo?.packageId,
           repo.extensions.contains(where: { $0.packageId == playingPackageId }) {
            statusMessage = "Không thể xóa kho đang được TTS sử dụng. Hãy dừng TTS trước."
            return
        }

        for ext in repo.extensions where !ext.localPath.isEmpty {
            ExtensionManager.shared.uninstall(localPath: ext.localPath)
        }
        let result = ExtensionTransactionCoordinator.shared.deleteRepository(url: repo.url, in: modelContext)
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
}
