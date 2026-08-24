import Foundation
import SwiftData

/// Lượt **tự động** sao lưu lên Google Drive: dựng archive → tải lên → dọn bản cũ, giữ tối đa
/// `DriveAutoBackupPolicy.maxVersions` bản.
///
/// Cùng khuôn với lượt kiểm tra chương mới: cửa mở/đóng do
/// [`DriveAutoBackupPolicy`](DriveAutoBackupPolicy.swift) quyết định, và hàm **trả về** kết quả cho
/// View tự hiện toast (`Sources/Services/**` không được gọi `ToastManager`).
///
/// Việc dọn chỉ chạm file tên `freebook-auto-*` — bản người dùng tự tạo, tự đổi tên hoặc tải lên
/// bằng tay không bao giờ bị xoá hộ, dù nằm cùng thư mục trên Drive.
extension BackupCoordinator {
    public enum AutoDriveBackupOutcome: Sendable, Equatable {
        /// Chưa tới lượt, chưa đăng nhập Drive, hoặc đang có việc sao lưu khác chạy — View im lặng.
        case skipped
        case succeeded(fileName: String, size: String, prunedRemote: Int, prunedLocal: Int)
        case failed(String)
    }

    /// `force == true` là đường bấm tay trong Cài đặt: bỏ qua cooldown và cả cờ bật/tắt, nhưng vẫn
    /// cần đã đăng nhập Drive và không có việc khác đang chạy.
    @discardableResult
    public func runAutoDriveBackup(container: ModelContainer, force: Bool = false) async -> AutoDriveBackupOutcome {
        guard GoogleDriveConfiguration.isConfigured, isDriveSignedIn else { return .skipped }
        guard !isBusy else { return .skipped }
        guard force || DriveAutoBackupPolicy.shouldRun() else { return .skipped }

        // Đánh dấu trước khi làm việc nặng: thất bại thì chờ tới lượt sau, không nén lại mỗi lần mở app.
        DriveAutoBackupPolicy.markRun()
        setBusy(true)
        defer { setBusy(false) }

        let scopes = DriveAutoBackupPolicy.scopes
        let destination = BackupPaths.backupsDirectory
            .appendingPathComponent(BackupPaths.makeAutoBackupFileName())
        setProgress(BackupProgress(phase: .readingLibrary))

        do {
            let worker = BackupExportWorker(container: container, scopes: scopes, report: autoReporter())
            let archive = try await worker.export(destination: destination)

            setProgress(BackupProgress(phase: .uploading, detail: archive.fileURL.lastPathComponent))
            _ = try await GoogleDriveUploader.shared.upload(fileURL: archive.fileURL, report: autoReporter())

            let prunedRemote = await pruneRemoteAutoBackups()
            let prunedLocal = pruneLocalAutoBackups()
            refreshLocal()
            await refreshDriveFiles()

            let size = BackupSizeEstimator.format(BackupPaths.fileSize(at: archive.fileURL))
            setProgress(BackupProgress(phase: .finished, detail: size))
            AppLogger.shared.log(
                "☁️ [AutoBackup] Đã tải lên \(archive.fileURL.lastPathComponent) — \(size);"
                + " dọn \(prunedRemote) bản trên Drive, \(prunedLocal) bản trong máy"
            )
            return .succeeded(
                fileName: archive.fileURL.lastPathComponent,
                size: size,
                prunedRemote: prunedRemote,
                prunedLocal: prunedLocal
            )
        } catch {
            setProgress(BackupProgress(phase: .failed, detail: error.localizedDescription))
            AppLogger.shared.log("⚠️ [AutoBackup] Thất bại: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Dọn bản cũ

    /// Giữ `maxVersions` bản tự động mới nhất trên Drive. Xoá lỗi một file thì bỏ qua file đó —
    /// bản vừa tải lên vẫn còn nguyên nên không có gì phải rollback.
    private func pruneRemoteAutoBackups() async -> Int {
        let files: [GoogleDriveFile]
        do {
            files = try await GoogleDriveClient.shared.listBackups()
        } catch {
            AppLogger.shared.log("⚠️ [AutoBackup] Không đọc được danh sách Drive để dọn: \(error.localizedDescription)")
            return 0
        }

        let stale = files
            .filter { BackupPaths.isAutoBackupFileName($0.name) }
            .sorted { $0.createdAt > $1.createdAt }
            .dropFirst(DriveAutoBackupPolicy.maxVersions)

        var removed = 0
        for file in stale {
            do {
                try await GoogleDriveClient.shared.delete(fileId: file.id)
                removed += 1
            } catch {
                AppLogger.shared.log("⚠️ [AutoBackup] Không xoá được \(file.name) trên Drive: \(error.localizedDescription)")
            }
        }
        return removed
    }

    /// `LocalBackupStore.list()` đã sắp mới nhất lên đầu nên chỉ cần bỏ phần đầu danh sách.
    private func pruneLocalAutoBackups() -> Int {
        let stale = LocalBackupStore.list()
            .filter { BackupPaths.isAutoBackupFileName($0.name) }
            .dropFirst(DriveAutoBackupPolicy.maxVersions)

        var removed = 0
        for item in stale {
            do {
                try LocalBackupStore.delete(item)
                removed += 1
            } catch {
                AppLogger.shared.log("⚠️ [AutoBackup] Không xoá được \(item.name) trong máy: \(error.localizedDescription)")
            }
        }
        return removed
    }

    private func autoReporter() -> @Sendable (BackupProgress) -> Void {
        { [weak self] value in
            Task { @MainActor in
                self?.setProgress(value)
            }
        }
    }
}
