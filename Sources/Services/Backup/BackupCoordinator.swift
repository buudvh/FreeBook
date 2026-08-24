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
        await performRestore(prepared: prepared, container: container, options: options)
        isBusy = false
    }

    /// Thân khôi phục dùng chung cho cả luồng có hộp thoại và luồng một-chạm từ Drive.
    /// Caller chịu trách nhiệm bật/tắt `isBusy` — hàm này không tự khoá để chuỗi tải-về-rồi-khôi-phục
    /// không tự chặn chính nó.
    private func performRestore(
        prepared: BackupRestoreWorker.Prepared,
        container: ModelContainer,
        options: BackupRestoreWorker.Options
    ) async {
        let worker = BackupRestoreWorker(
            container: container,
            prepared: prepared,
            options: options,
            report: makeReporter()
        )
        let outcome = await worker.restore()
        cancelPreparedRestore()

        if outcome.errors.isEmpty {
            var message = "Đã khôi phục \(outcome.library.insertedBooks) truyện mới,"
                + " \(outcome.chapters.restoredChapters) chương"
            if outcome.covers.restoredCovers > 0 {
                message += ", \(outcome.covers.restoredCovers) ảnh bìa"
            }
            if outcome.config.searchEngines > 0 {
                message += ", \(outcome.config.searchEngines) công cụ tra cứu"
            }
            if outcome.settings.restoredKeys > 0 {
                message += ". Mở lại app để cài đặt có hiệu lực"
            }
            lastMessage = message
        } else {
            lastError = "Khôi phục xong nhưng có \(outcome.errors.count) lỗi: \(outcome.errors[0])"
        }
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

    /// Chặn khi đang có việc chạy: đăng xuất giữa lúc tải/khôi phục là thu hồi access token mà
    /// worker đang dùng — request đang bay sẽ chết giữa đường và archive dở dang.
    public func signOutDrive() {
        guard !isBusy else {
            lastError = "Đang tải dữ liệu từ Google Drive, không thể đăng xuất lúc này"
            return
        }
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
            let temporaryURL = try await GoogleDriveClient.shared.download(
                file: file,
                report: makeReporter()
            )
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

    /// Khôi phục một-chạm từ Drive: tải về → nhập vào `backups/` → đọc manifest → ghi **toàn bộ**
    /// nhóm dữ liệu, không hiện hộp thoại chọn nhóm. Cả chuỗi chạy dưới một lần khoá `isBusy`.
    ///
    /// Không ghi đè từ điển chung (`overwriteSharedDictionaries: false`) — nhóm đó chỉ được cài khi
    /// máy này còn thiếu file, đúng như luồng khôi phục có hộp thoại khi người dùng không tick.
    public func restoreEverythingFromDrive(_ file: GoogleDriveFile, container: ModelContainer) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        progress = BackupProgress(phase: .downloading, detail: file.name)
        let archiveURL: URL
        do {
            let temporaryURL = try await GoogleDriveClient.shared.download(
                file: file,
                report: makeReporter()
            )
            defer { try? FileManager.default.removeItem(at: temporaryURL.deletingLastPathComponent()) }
            archiveURL = try LocalBackupStore.importArchive(from: temporaryURL).url
            refreshLocal()
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = "Tải xuống thất bại: \(error.localizedDescription)"
            return
        }

        progress = BackupProgress(phase: .extracting, detail: file.name)
        cancelPreparedRestore()
        do {
            let prepared = try await Task.detached(priority: .userInitiated) {
                try BackupRestoreWorker.prepare(archive: archiveURL)
            }.value
            await performRestore(
                prepared: prepared,
                container: container,
                options: BackupRestoreWorker.Options(scopes: BackupScope.defaultSelection)
            )
        } catch {
            progress = BackupProgress(phase: .failed, detail: error.localizedDescription)
            lastError = error.localizedDescription
        }
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

    /// `isBusy` / `progress` là `private(set)` nên extension ở **file khác** không ghi được.
    /// Hai hàm này là cửa duy nhất cho phần tự động sao lưu
    /// ([`BackupCoordinator+AutoDrive`](BackupCoordinator+AutoDrive.swift)) dùng chung một khoá
    /// `isBusy` với các luồng bấm tay — đừng gọi từ tầng View.
    func setBusy(_ value: Bool) {
        isBusy = value
    }

    func setProgress(_ value: BackupProgress) {
        progress = value
    }

    private func makeReporter() -> @Sendable (BackupProgress) -> Void {
        { [weak self] value in
            Task { @MainActor in
                self?.progress = value
            }
        }
    }
}
