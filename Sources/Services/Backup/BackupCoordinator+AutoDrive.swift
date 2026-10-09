import Foundation
import SwiftData

/// Lượt tự động dùng chung: dựng một archive rồi gửi độc lập tới Drive và Telegram đã bật.
///
/// Cùng khuôn với lượt kiểm tra chương mới: cửa mở/đóng do
/// [`DriveAutoBackupPolicy`](DriveAutoBackupPolicy.swift) quyết định, và hàm **trả về** kết quả cho
/// View tự hiện toast (`Sources/Services/**` không được gọi `ToastManager`).
///
/// Việc dọn chỉ chạm file tên `freebook-auto-*` — bản người dùng tự tạo, tự đổi tên hoặc tải lên
/// bằng tay không bao giờ bị xoá hộ, dù nằm cùng thư mục trên Drive.
///
/// Lượt **theo lịch** còn qua cổng "không có gì đổi" ([`BackupLibraryFingerprint`](BackupLibraryFingerprint.swift)):
/// archive sẽ y hệt bản thành công gần nhất thì không nén, không gửi — nếu không, các bản trùng nhau sẽ
/// đẩy những phiên bản khác nhau cuối cùng ra khỏi `maxVersions`. Mọi đường bấm tay không qua cổng.
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
            case telegramNotConfigured
        }

        case skipped(SkipReason)
        case completed(
            fileName: String,
            size: String,
            driveSent: Bool,
            telegramSent: Bool,
            failures: [String],
            prunedRemote: Int,
            prunedLocal: Int,
            pruneIncomplete: Bool
        )
        case failed(String)

        /// Hậu tố cho toast, nói về việc dọn bản cũ. Dùng chung cho cả hai đường (tự động và bấm tay)
        /// để câu chữ hai chỗ không trôi khỏi nhau; rỗng khi không có gì đáng nói.
        public var pruneNote: String {
            guard case .completed(_, _, _, _, _, let prunedRemote, let prunedLocal, let pruneIncomplete) = self else {
                return ""
            }
            if pruneIncomplete { return " — chưa dọn hết bản cũ" }
            let pruned = prunedRemote + prunedLocal
            return pruned > 0 ? " — đã dọn \(pruned) bản cũ" : ""
        }
    }

    /// Kết quả của lượt **theo lịch** (`MainTabView`). Tách khỏi `AutoDriveBackupOutcome` vì cổng "không có
    /// gì đổi" chỉ áp cho lượt theo lịch: thêm case vào `AutoDriveBackupOutcome` sẽ bắt `switch` của đường
    /// bấm tay (`DriveAutoBackupSettingsView`) xử lý một kết quả nó không bao giờ nhận.
    public enum ScheduledAutoBackupOutcome: Sendable, Equatable {
        /// Tới kỳ nhưng mọi thứ archive sẽ chứa vẫn y như lượt thành công trọn vẹn gần nhất. Kỳ này đã
        /// được tính là xong (`markRun`, như một lượt chạy thật) — View im lặng.
        case unchanged
        case ran(AutoDriveBackupOutcome)
    }

    /// Lượt theo lịch: như `runAutoDriveBackup(force: false)`, nhưng trả riêng kết quả "không có gì đổi".
    public func runScheduledAutoBackup(container: ModelContainer) async -> ScheduledAutoBackupOutcome {
        await runAutoBackupPass(container: container, force: false)
    }

    /// `force == true` là đường bấm tay trong Cài đặt: bỏ qua cooldown **và** cổng "không có gì đổi",
    /// nhưng chỉ gửi tới các đích đang bật và vẫn dùng chung khoá với mọi việc sao lưu khác.
    @discardableResult
    public func runAutoDriveBackup(container: ModelContainer, force: Bool = false) async -> AutoDriveBackupOutcome {
        switch await runAutoBackupPass(container: container, force: force) {
        case .ran(let outcome):
            return outcome
        case .unchanged:
            // Chỉ lượt không ép mới gặp cổng; với người gọi kiểu cũ, "không có gì phải làm" là `notDue` (im lặng).
            return .skipped(.notDue)
        }
    }

    private func runAutoBackupPass(container: ModelContainer, force: Bool) async -> ScheduledAutoBackupOutcome {
        let wantsDrive = DriveAutoBackupPolicy.isEnabled
        let wantsTelegram = DriveAutoBackupPolicy.isTelegramEnabled
        guard wantsDrive || wantsTelegram else { return .ran(.skipped(.notDue)) }
        if wantsDrive && (!GoogleDriveConfiguration.isConfigured || !isDriveSignedIn) && !wantsTelegram {
            // Đường bấm tay luôn được trả lời ngay; lượt tự động thì nhắc theo nhịp của policy.
            guard !force else { return .ran(.skipped(.driveNotLinked)) }
            guard DriveAutoBackupPolicy.shouldWarnDriveNotLinked() else { return .ran(.skipped(.notDue)) }
            DriveAutoBackupPolicy.markDriveNotLinkedWarned()
            return .ran(.skipped(.driveNotLinked))
        }
        if wantsTelegram && !TelegramConfiguration.isConfigured && !wantsDrive {
            return .ran(.skipped(.telegramNotConfigured))
        }
        guard !isBusy else { return .ran(.skipped(.notDue)) }
        guard force || DriveAutoBackupPolicy.shouldRun() else { return .ran(.skipped(.notDue)) }

        // Đánh dấu trước khi làm việc nặng: thất bại thì chờ tới lượt sau, không nén lại mỗi lần mở app.
        // Lượt bị cổng "không có gì đổi" chặn cũng đi qua đây nên kỳ này được tính là xong như lượt thật.
        DriveAutoBackupPolicy.markRun()
        setBusy(true)
        defer { setBusy(false) }

        let scopes = DriveAutoBackupPolicy.scopes
        setProgress(BackupProgress(phase: .readingLibrary))

        // Tính **trước** export (cả đường bấm tay, để lưu sau khi thành công). Bản tính này chưa chắc khớp
        // archive (export đọc lại sau đó, và tự nuốt lỗi đọc) — nên chỉ được lưu sau khi đối chiếu ở dưới.
        let fingerprintStart = Date()
        let fingerprint = await BackupLibraryFingerprint.compute(
            container: container,
            scopes: scopes,
            driveEnabled: wantsDrive,
            telegramEnabled: wantsTelegram
        )
        if !force, let fingerprint, DriveAutoBackupPolicy.isUnchanged(fingerprint: fingerprint.digest) {
            setProgress(.idle)
            let elapsedMs = Int(Date().timeIntervalSince(fingerprintStart) * 1000)
            AppLogger.shared.log("☁️ [Backup] Tự động sao lưu bỏ qua: không có thay đổi (so trong \(elapsedMs) ms)")
            return .unchanged
        }

        let destination = BackupPaths.backupsDirectory
            .appendingPathComponent(BackupPaths.makeAutoBackupFileName())

        do {
            let worker = BackupExportWorker(container: container, scopes: scopes, report: autoReporter())
            let archive = try await worker.export(destination: destination)
            let verifiedFingerprint = await fingerprintMatchingArchive(
                fingerprint,
                archive: archive,
                container: container,
                scopes: scopes,
                driveEnabled: wantsDrive,
                telegramEnabled: wantsTelegram
            )

            var driveSent = false
            var telegramSent = false
            var failures: [String] = []
            if wantsDrive {
                if GoogleDriveConfiguration.isConfigured, isDriveSignedIn {
                    do {
                        setProgress(BackupProgress(phase: .uploading, detail: "Google Drive"))
                        _ = try await GoogleDriveUploader.shared.upload(fileURL: archive.fileURL, report: autoReporter())
                        driveSent = true
                    } catch {
                        failures.append("Drive: \(error.localizedDescription)")
                    }
                } else {
                    failures.append("Drive: chưa đăng nhập")
                }
            }
            if wantsTelegram {
                if TelegramConfiguration.isConfigured {
                    do {
                        setProgress(BackupProgress(phase: .uploading, detail: "Telegram"))
                        _ = try await TelegramBackupUploader.shared.upload(fileURL: archive.fileURL, report: autoReporter())
                        telegramSent = true
                    } catch {
                        failures.append("Telegram: \(error.localizedDescription)")
                    }
                } else {
                    failures.append("Telegram: chưa cấu hình")
                }
            }

            // Chỉ lượt mà mọi đích đang bật đều nhận được archive mới được thay dấu vân tay; lỗi dọn bản cũ
            // không tính (archive mới đã tới nơi).
            if let verifiedFingerprint, failures.isEmpty, driveSent == wantsDrive, telegramSent == wantsTelegram {
                DriveAutoBackupPolicy.recordSuccessfulRun(
                    fingerprint: verifiedFingerprint,
                    archiveName: archive.fileURL.lastPathComponent
                )
            }

            let prunedRemote: (removed: Int, incomplete: Bool) = driveSent
                ? await pruneRemoteAutoBackups()
                : (removed: 0, incomplete: false)
            let prunedLocal = pruneLocalAutoBackups()
            refreshLocal()
            if driveSent { await refreshDriveFiles() }

            let size = BackupSizeEstimator.format(BackupPaths.fileSize(at: archive.fileURL))
            setProgress(BackupProgress(phase: .finished, detail: size))
            AppLogger.shared.log(
                "☁️ [AutoBackup] Đã xử lý \(archive.fileURL.lastPathComponent) — \(size);"
                + " dọn \(prunedRemote.removed) bản trên Drive, \(prunedLocal.removed) bản trong máy"
                + (prunedRemote.incomplete || prunedLocal.incomplete ? "; còn bản cũ chưa dọn được" : "")
            )
            return .ran(.completed(
                fileName: archive.fileURL.lastPathComponent,
                size: size,
                driveSent: driveSent,
                telegramSent: telegramSent,
                failures: failures,
                prunedRemote: prunedRemote.removed,
                prunedLocal: prunedLocal.removed,
                pruneIncomplete: prunedRemote.incomplete || prunedLocal.incomplete
            ))
        } catch {
            setProgress(BackupProgress(phase: .failed, detail: error.localizedDescription))
            AppLogger.shared.log("⚠️ [AutoBackup] Thất bại: \(error.localizedDescription)")
            return .ran(.failed(error.localizedDescription))
        }
    }

    /// Digest được phép lưu cho archive vừa dựng, hoặc `nil` (giữ dấu vân tay cũ ⇒ kỳ sau chạy lại) khi
    /// không chắc archive chứa đúng trạng thái đã băm:
    /// - số lượng trong `manifest.counts` lệch số lần đọc trước thấy — export nuốt lỗi đọc (`try?`) nên
    ///   archive có thể thiếu mục lục/truyện mà vẫn "thành công";
    /// - băm lại sau export ra khác — có thay đổi xen giữa hai lần đọc, archive có thể mang trạng thái
    ///   khác với digest (đổi rồi đổi lại sau đó sẽ khớp nhầm mãi). Không bao giờ lưu riêng bản sau
    ///   export: nó có thể che một thay đổi xảy ra sau khi export đã đọc qua.
    private func fingerprintMatchingArchive(
        _ fingerprint: BackupLibraryFingerprint.Value?,
        archive: BackupExportWorker.Outcome,
        container: ModelContainer,
        scopes: Set<BackupScope>,
        driveEnabled: Bool,
        telegramEnabled: Bool
    ) async -> String? {
        guard let fingerprint else { return nil }
        guard fingerprint.matches(archive.manifest.counts) else {
            let counts = archive.manifest.counts
            AppLogger.shared.log(
                "⚠️ [Backup] Archive lệch lần đọc để so thay đổi (\(counts.books)/\(fingerprint.books) truyện,"
                + " \(counts.chapters)/\(fingerprint.tocRows) chương) — không lưu dấu vân tay"
            )
            return nil
        }
        let after = await BackupLibraryFingerprint.compute(
            container: container,
            scopes: scopes,
            driveEnabled: driveEnabled,
            telegramEnabled: telegramEnabled
        )
        guard after == fingerprint else {
            AppLogger.shared.log("☁️ [Backup] Thư viện đổi trong lúc sao lưu — không lưu dấu vân tay, kỳ sau chạy lại")
            return nil
        }
        return fingerprint.digest
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
                self?.publishReportedProgress(value)
            }
        }
    }
}
