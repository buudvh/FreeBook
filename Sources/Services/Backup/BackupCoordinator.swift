import Combine
import Foundation
import SwiftData

/// Cầu nối giữa UI và các worker sao lưu. Giữ toàn bộ trạng thái mà màn Sao lưu cần hiển thị;
/// View chỉ đọc `@Published` và gọi các hàm ở đây, không tự tạo worker.
///
/// Không hiện toast từ đây (`Sources/Services/**` không được gọi `ToastManager`) — View đọc
/// `lastMessage` / `lastError` rồi tự hiện.
@MainActor
public final class BackupCoordinator: ObservableObject {
    public static let shared = BackupCoordinator()

    @Published public private(set) var progress: BackupProgress = .idle
    @Published public private(set) var isBusy = false
    @Published public private(set) var localBackups: [LocalBackupStore.Item] = []
    @Published public private(set) var driveFiles: [GoogleDriveFile] = []
    @Published public private(set) var isDriveSignedIn = false
    @Published public private(set) var preparedRestore: BackupRestoreWorker.Prepared?
    @Published public var lastMessage: String?
    @Published public var lastError: String?

    private init() {
        isDriveSignedIn = GoogleDriveTokenStore.hasRefreshToken
    }

    // MARK: - Kênh local

    public func refreshLocal() {
        localBackups = LocalBackupStore.list()
    }

    public func createBackup(container: ModelContainer, scopes: Set<BackupScope>) async {
        guard !isBusy else { return }
        isBusy = true
        progress = BackupProgress(phase: .readingLibrary)

        let worker = BackupExportWorker(container: container, scopes: scopes, report: makeReporter())
        do {
            let outcome = try await worker.export()
            refreshLocal()
            let size = BackupSizeEstimator.format(BackupPaths.fileSize(at: outcome.fileURL))
            lastMessage = "Đã tạo bản sao lưu (\(size))"
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = "Sao lưu thất bại: \(error.localizedDescription)"
        }
        isBusy = false
    }

    public func deleteLocal(_ item: LocalBackupStore.Item) {
        do {
            try LocalBackupStore.delete(item)
            refreshLocal()
        } catch {
            lastError = "Không xoá được: \(error.localizedDescription)"
        }
    }

    public func renameLocal(_ item: LocalBackupStore.Item, to newName: String) {
        do {
            _ = try LocalBackupStore.rename(item, to: newName)
            refreshLocal()
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Chép file người dùng chọn từ Files vào `backups/`.
    public func importFromFiles(url: URL) {
        do {
            _ = try LocalBackupStore.importArchive(from: url)
            refreshLocal()
            lastMessage = "Đã thêm bản sao lưu vào danh sách"
        } catch {
            lastError = "Không nhập được file: \(error.localizedDescription)"
        }
    }

    // MARK: - Khôi phục

    /// Giải nén + đọc manifest để UI hỏi lại người dùng trước khi ghi.
    public func prepareRestore(from archive: URL) async {
        guard !isBusy else { return }
        isBusy = true
        progress = BackupProgress(phase: .extracting)
        cancelPreparedRestore()

        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try BackupRestoreWorker.prepare(archive: archive)
            }.value
            preparedRestore = prepared
            progress = .idle
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = error.localizedDescription
        }
        isBusy = false
    }

    public func cancelPreparedRestore() {
        preparedRestore?.cleanUp()
        preparedRestore = nil
    }

    public func runRestore(container: ModelContainer, options: BackupRestoreWorker.Options) async {
        guard let prepared = preparedRestore, !isBusy else { return }
        isBusy = true

        let worker = BackupRestoreWorker(
            container: container,
            prepared: prepared,
            options: options,
            report: makeReporter()
        )
        let outcome = await worker.restore()
        cancelPreparedRestore()

        if outcome.errors.isEmpty {
            lastMessage = "Đã khôi phục \(outcome.library.insertedBooks) truyện mới,"
                + " \(outcome.chapters.restoredChapters) chương"
        } else {
            lastError = "Khôi phục xong nhưng có \(outcome.errors.count) lỗi: \(outcome.errors[0])"
        }
        isBusy = false
    }

    // MARK: - Google Drive

    public func signInDrive() async {
        do {
            try await GoogleDriveAuthService.shared.signIn()
            isDriveSignedIn = true
            await refreshDriveFiles()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func signOutDrive() {
        GoogleDriveAuthService.shared.signOut()
        isDriveSignedIn = false
        driveFiles = []
        Task { await GoogleDriveClient.shared.resetCache() }
    }

    public func refreshDriveFiles() async {
        guard GoogleDriveConfiguration.isConfigured, isDriveSignedIn else { return }
        do {
            driveFiles = try await GoogleDriveClient.shared.listBackups()
        } catch {
            lastError = error.localizedDescription
        }
    }

    public func uploadToDrive(_ item: LocalBackupStore.Item) async {
        guard !isBusy else { return }
        isBusy = true
        progress = BackupProgress(phase: .uploading, detail: item.name)
        do {
            _ = try await GoogleDriveUploader.shared.upload(fileURL: item.url, report: makeReporter())
            await refreshDriveFiles()
            lastMessage = "Đã tải lên Google Drive"
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = "Tải lên thất bại: \(error.localizedDescription)"
        }
        isBusy = false
    }

    /// Tải file Drive về rồi đưa vào `backups/` để dùng như bản local.
    public func downloadFromDrive(_ file: GoogleDriveFile) async {
        guard !isBusy else { return }
        isBusy = true
        progress = BackupProgress(phase: .downloading, detail: file.name)
        do {
            let temporaryURL = try await GoogleDriveClient.shared.download(file: file)
            defer { try? FileManager.default.removeItem(at: temporaryURL.deletingLastPathComponent()) }
            _ = try LocalBackupStore.importArchive(from: temporaryURL)
            refreshLocal()
            progress = BackupProgress(phase: .finished, detail: file.name)
            lastMessage = "Đã tải \(file.name) về máy"
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = "Tải xuống thất bại: \(error.localizedDescription)"
        }
        isBusy = false
    }

    public func deleteFromDrive(_ file: GoogleDriveFile) async {
        do {
            try await GoogleDriveClient.shared.delete(fileId: file.id)
            await refreshDriveFiles()
        } catch {
            lastError = "Không xoá được trên Drive: \(error.localizedDescription)"
        }
    }

    // MARK: - Hạ tầng

    private func makeReporter() -> @Sendable (BackupProgress) -> Void {
        { [weak self] value in
            Task { @MainActor in
                self?.progress = value
            }
        }
    }
}
