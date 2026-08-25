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
        /// Vì sao lượt không chạy — quyết định View im lặng hay phải nhắc.
        public enum SkipReason: Sendable, Equatable {
            /// Chưa tới lượt, đang có việc sao lưu khác chạy, hoặc bản build không nhúng client id
            /// Drive (người dùng không làm gì được) — View im lặng.
            case notDue
            /// Đã tới kỳ và cờ tự động đang bật, nhưng chưa đăng nhập Drive. Phải nhắc, nếu không
            /// lượt sao lưu im lặng không chạy mãi.
            case driveNotLinked
        }

        case skipped(SkipReason)
        case succeeded(fileName: String, size: String, prunedRemote: Int, prunedLocal: Int, pruneIncomplete: Bool)
        case failed(String)

        /// Hậu tố cho toast, nói về việc dọn bản cũ. Dùng chung cho cả hai đường (tự động và bấm tay)
        /// để câu chữ hai chỗ không trôi khỏi nhau; rỗng khi không có gì đáng nói.
        public var pruneNote: String {
            guard case .succeeded(_, _, let prunedRemote, let prunedLocal, let pruneIncomplete) = self else { return "" }
            if pruneIncomplete { return " — chưa dọn hết bản cũ" }
            let pruned = prunedRemote + prunedLocal
            return pruned > 0 ? " — đã dọn \(pruned) bản cũ" : ""
        }
    }

    /// `force == true` là đường bấm tay trong Cài đặt: bỏ qua cooldown và cả cờ bật/tắt, nhưng vẫn
    /// cần đã đăng nhập Drive và không có việc khác đang chạy.
    @discardableResult
    public func runAutoDriveBackup(container: ModelContainer, force: Bool = false) async -> AutoDriveBackupOutcome {
        guard GoogleDriveConfiguration.isConfigured else { return .skipped(.notDue) }
        guard isDriveSignedIn else {
            // Đường bấm tay luôn được trả lời ngay; lượt tự động thì nhắc theo nhịp của policy.
            guard !force else { return .skipped(.driveNotLinked) }
            guard DriveAutoBackupPolicy.shouldWarnDriveNotLinked() else { return .skipped(.notDue) }
            DriveAutoBackupPolicy.markDriveNotLinkedWarned()
            return .skipped(.driveNotLinked)
        }
        guard !isBusy else { return .skipped(.notDue) }
        guard force || DriveAutoBackupPolicy.shouldRun() else { return .skipped(.notDue) }

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
                + " dọn \(prunedRemote.removed) bản trên Drive, \(prunedLocal.removed) bản trong máy"
                + (prunedRemote.incomplete || prunedLocal.incomplete ? "; còn bản cũ chưa dọn được" : "")
            )
            return .succeeded(
                fileName: archive.fileURL.lastPathComponent,
                size: size,
                prunedRemote: prunedRemote.removed,
                prunedLocal: prunedLocal.removed,
                pruneIncomplete: prunedRemote.incomplete || prunedLocal.incomplete
            )
        } catch {
            setProgress(BackupProgress(phase: .failed, detail: error.localizedDescription))
            AppLogger.shared.log("⚠️ [AutoBackup] Thất bại: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
    }

    // MARK: - Dọn bản cũ

    /// Giữ `maxVersions` bản tự động mới nhất trên Drive. Xoá lỗi một file thì bỏ qua file đó —
    /// bản vừa tải lên vẫn còn nguyên nên không có gì phải rollback. `incomplete == true` nghĩa là
    /// còn bản cũ nằm lại: toast phải nói ra, nếu không Drive phình quá `maxVersions` mà không ai biết.
    private func pruneRemoteAutoBackups() async -> (removed: Int, incomplete: Bool) {
        let files: [GoogleDriveFile]
        do {
            files = try await GoogleDriveClient.shared.listBackups()
        } catch {
            AppLogger.shared.log("⚠️ [AutoBackup] Không đọc được danh sách Drive để dọn: \(error.localizedDescription)")
            return (0, true)
        }

        let stale = files
            .filter { BackupPaths.isAutoBackupFileName($0.name) }
            .sorted { $0.createdAt > $1.createdAt }
            .dropFirst(DriveAutoBackupPolicy.maxVersions)

        var removed = 0
        var incomplete = false
        for file in stale {
            do {
                try await GoogleDriveClient.shared.delete(fileId: file.id)
                removed += 1
            } catch {
                incomplete = true
                AppLogger.shared.log("⚠️ [AutoBackup] Không xoá được \(file.name) trên Drive: \(error.localizedDescription)")
            }
        }
        return (removed, incomplete)
    }

    /// `LocalBackupStore.list()` đã sắp mới nhất lên đầu nên chỉ cần bỏ phần đầu danh sách.
    private func pruneLocalAutoBackups() -> (removed: Int, incomplete: Bool) {
        let stale = LocalBackupStore.list()
            .filter { BackupPaths.isAutoBackupFileName($0.name) }
            .dropFirst(DriveAutoBackupPolicy.maxVersions)

        var removed = 0
        var incomplete = false
        for item in stale {
            do {
                try LocalBackupStore.delete(item)
                removed += 1
            } catch {
                incomplete = true
                AppLogger.shared.log("⚠️ [AutoBackup] Không xoá được \(item.name) trong máy: \(error.localizedDescription)")
            }
        }
        return (removed, incomplete)
    }

    private func autoReporter() -> @Sendable (BackupProgress) -> Void {
        { [weak self] value in
            Task { @MainActor in
                self?.setProgress(value)
            }
        }
    }
}
