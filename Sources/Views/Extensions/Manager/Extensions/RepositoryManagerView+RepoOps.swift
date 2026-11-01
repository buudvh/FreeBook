import SwiftUI

/// Cài một tiện ích của kho và import zip.
///
/// Thêm / làm mới / xoá **kho** chuyển sang trang con `ExtensionRepositoryListView` + `ExtensionUpdateCheckCoordinator`
/// (1.3.673). Làm mới/thêm kho vẫn chỉ tốn **1 request registry/kho**: lưu nguyên văn registry vào cache
/// (`saveRegistry`), danh mục tiện ích chưa cài được `ExtensionLibraryRepository.catalog` dựng từ cache đó.
extension RepositoryManagerView {
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
}
