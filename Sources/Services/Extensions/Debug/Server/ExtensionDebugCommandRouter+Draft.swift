import Foundation
import SwiftData

/// Nhánh `draft.*` của router: nạp snapshot nháp (Phase 3), cài / cài mới và rollback (Phase 4–5).
///
/// Trình tự bắt buộc, cưỡng chế bằng chính state của `ExtensionDraftStagingStore`:
/// `draft.stage` (manifest) → nhiều `draft.chunk` → `draft.finish` (checksum + validate) → `run.start`
/// với `sourceMode: "draft"`. Không có đường nào để `run.start` chạy một revision chưa qua `finish`.
///
/// `draft.install` / `draft.rollback` **không bao giờ** tự chạy: chúng treo ở
/// `ExtensionDebugInstallGate` cho tới khi người dùng bấm trên thiết bị, và người bấm thấy trước danh
/// sách file sẽ đổi.
extension ExtensionDebugCommandRouter {
    internal func handleDraft(
        _ type: ExtensionDebugProtocol.CommandType,
        _ envelope: ExtensionDebugProtocol.Envelope
    ) async {
        switch type {
        case .draftStage:
            await handleDraftStage(envelope)
        case .draftChunk:
            await handleDraftChunk(envelope)
        case .draftFinish:
            await handleDraftFinish(envelope)
        case .draftDiscard:
            await handleDraftDiscard(envelope)
        case .draftInstall:
            await handleDraftInstall(envelope)
        case .draftRollback:
            await handleDraftRollback(envelope)
        default:
            break
        }
    }

    private func handleDraftStage(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let manifest = envelope.payload?.manifest else {
            replyError(to: envelope, code: .malformedMessage, message: "Thiếu manifest")
            return
        }
        // **Không** đòi extension đã có trên app nữa: từ 1.3.325, bản nháp của một extension chưa cài là
        // đầu vào hợp lệ của `draft.install` (đường cài mới). Chốt an toàn của vùng staging không phải là
        // "đã cài hay chưa" mà là trần của `ExtensionDraftManifest` (200 file / 1 MiB mỗi file / 4 MiB
        // tổng), kiểm tra containment từng path, và việc staging bị xoá sạch khi tắt server hoặc mở lại
        // app. Ghi vào thư viện thì vẫn phải bấm trên thiết bị, ở `draft.install`.
        let issues = await ExtensionDraftStagingStore.shared.beginStage(manifest)
        guard issues.isEmpty else {
            // Vượt trần dung lượng là điều kiện chặn **khác hẳn** "manifest sai": một cái bắt người
            // dùng bớt file, một cái bắt sửa manifest. `QUOTA_EXCEEDED` khai trong giao thức từ đầu mà
            // chưa chỗ nào phát — đo bằng client thật: manifest 300 file trả `DRAFT_INVALID`.
            //
            // Có **bất kỳ** vấn đề dung lượng ⇒ `QUOTA_EXCEEDED`, kể cả khi manifest còn lỗi khác: trần
            // là thứ phải sửa trước, sửa manifest không cứu được workspace 10 MiB. Mảng `issues` vẫn
            // mang đủ mọi vấn đề nên client hiện được cả danh sách.
            let code: ExtensionDebugProtocol.ErrorCode = manifest.quotaIssues().isEmpty
                ? .draftInvalid
                : .quotaExceeded
            replyIssues(to: envelope, code: code, issues: issues)
            return
        }
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    private func handleDraftChunk(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let relativePath = envelope.payload?.relativePath,
              let base64 = envelope.payload?.chunkBase64,
              let data = Data(base64Encoded: base64) else {
            replyError(to: envelope, code: .malformedMessage, message: "Chunk thiếu path hoặc dữ liệu base64")
            return
        }
        do {
            try await ExtensionDraftStagingStore.shared.appendChunk(relativePath: relativePath, data: data)
            reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
        } catch {
            replyError(to: envelope, code: .draftInvalid, message: error.localizedDescription)
        }
    }

    private func handleDraftFinish(_ envelope: ExtensionDebugProtocol.Envelope) async {
        let result = await ExtensionDraftStagingStore.shared.finishStage()
        guard let manifest = result.manifest, result.issues.isEmpty else {
            replyIssues(to: envelope, code: .draftInvalid, issues: result.issues)
            return
        }
        guard let directory = await ExtensionDraftStagingStore.shared.draftDirectory(
            packageId: manifest.packageId,
            revision: manifest.revision
        ) else {
            replyError(to: envelope, code: .internalError, message: "Không resolve được thư mục staging")
            return
        }
        let validationIssues = ExtensionDraftValidator.validate(directory: directory, manifest: manifest)
        guard validationIssues.isEmpty else {
            await ExtensionDraftStagingStore.shared.discard(packageId: manifest.packageId, revision: manifest.revision)
            replyIssues(to: envelope, code: .draftInvalid, issues: validationIssues)
            return
        }
        var payload = ExtensionDebugProtocol.Payload()
        payload.sourceRevision = manifest.revision
        reply(to: envelope, payload: payload)
    }

    private func handleDraftDiscard(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId,
              let revision = envelope.payload?.sourceRevision else {
            replyError(to: envelope, code: .malformedMessage, message: "Thiếu packageId hoặc sourceRevision")
            return
        }
        await ExtensionDraftStagingStore.shared.discard(packageId: packageId, revision: revision)
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    // MARK: - Phase 4–5 (ghi đè / cài mới / rollback)

    private func handleDraftInstall(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId,
              let revision = envelope.payload?.sourceRevision else {
            replyError(to: envelope, code: .malformedMessage, message: "Thiếu packageId hoặc sourceRevision")
            return
        }
        guard await ExtensionDraftStagingStore.shared.hasDraft(packageId: packageId, revision: revision),
              let directory = await ExtensionDraftStagingStore.shared.draftDirectory(packageId: packageId, revision: revision) else {
            replyError(to: envelope, code: .draftMissing, message: "Chưa có bản nháp đã validate")
            return
        }

        // App là thẩm quyền về danh tính: id thật đọc từ `plugin.json` của bản nháp, **không** lấy từ
        // client. Nhờ vậy client gửi `Truyen Full` trong khi app đang có `truyen_full` vẫn được nhận
        // diện là *cập nhật*, không sinh hàng SwiftData thứ hai cho cùng một extension.
        let metadata: ExtensionDraftMetadata
        do {
            metadata = try ExtensionDraftMetadata.read(from: directory)
        } catch {
            replyError(to: envelope, code: .draftInvalid, message: error.localizedDescription)
            return
        }

        let installed = installedExtensions()
        let snapshot = installed.first(where: { $0.packageId == packageId })
            ?? installed.first(where: { $0.packageId == metadata.packageId })

        if let snapshot {
            await installOverExisting(envelope, directory: directory, revision: revision, snapshot: snapshot)
        } else {
            await installAsNew(envelope, directory: directory, revision: revision, metadata: metadata)
        }
    }

    private func installOverExisting(
        _ envelope: ExtensionDebugProtocol.Envelope,
        directory: URL,
        revision: String,
        snapshot: ExtensionDebugInstalledSnapshot
    ) async {
        let changes = await ExtensionDraftInstaller.shared.changeSummary(
            draftDirectory: directory,
            installedPath: snapshot.localPath
        )
        let request = ExtensionDebugInstallGate.Request(
            kind: .install,
            packageId: snapshot.packageId,
            revision: revision,
            changes: changes
        )
        guard await ExtensionDebugInstallGate.shared.requestApproval(request) == .approved else {
            replyError(to: envelope, code: .approvalRequired, message: "Người dùng không xác nhận trên thiết bị")
            return
        }
        do {
            try await ExtensionDraftInstaller.shared.install(
                draftDirectory: directory,
                installedPath: snapshot.localPath,
                packageId: snapshot.packageId
            )
            var payload = ExtensionDebugProtocol.Payload()
            payload.packageId = snapshot.packageId
            payload.message = "Đã cài \(changes.count) thay đổi; bản cũ được giữ để rollback"
            reply(to: envelope, payload: payload)
        } catch {
            replyError(to: envelope, code: .internalError, message: error.localizedDescription)
        }
    }

    /// Cài một extension **chưa có trên app**: dựng thư mục trong `extensions/` rồi ghi hàng `Extension`
    /// qua `ExtensionTransactionCoordinator`.
    ///
    /// Thứ tự **file trước, bản ghi sau** là bắt buộc: ghi bản ghi trước mà copy file thất bại thì thư
    /// viện có một extension trỏ vào thư mục không tồn tại — lỗi im lặng ở mọi màn đang `@Query`. Ngược
    /// lại, file có mà bản ghi chưa có chỉ là thư mục mồ côi: `ExtensionInstallAudit` phát hiện được, và
    /// lần cài sau tự sao lưu rồi thay.
    private func installAsNew(
        _ envelope: ExtensionDebugProtocol.Envelope,
        directory: URL,
        revision: String,
        metadata: ExtensionDraftMetadata
    ) async {
        let changes = await ExtensionDraftInstaller.shared.newInstallSummary(draftDirectory: directory)
        let request = ExtensionDebugInstallGate.Request(
            kind: .installNew,
            packageId: metadata.packageId,
            revision: revision,
            displayName: metadata.name,
            changes: changes
        )
        guard await ExtensionDebugInstallGate.shared.requestApproval(request) == .approved else {
            replyError(to: envelope, code: .approvalRequired, message: "Người dùng không xác nhận trên thiết bị")
            return
        }

        let installedPath: String
        do {
            installedPath = try await ExtensionDraftInstaller.shared.installNew(
                draftDirectory: directory,
                packageId: metadata.packageId
            )
        } catch {
            replyError(to: envelope, code: .internalError, message: error.localizedDescription)
            return
        }

        if let failure = await writeLibraryRow(metadata: metadata, localPath: installedPath) {
            replyError(
                to: envelope,
                code: .internalError,
                message: "Đã copy file nhưng không ghi được thư viện: \(failure)"
            )
            return
        }

        var payload = ExtensionDebugProtocol.Payload()
        payload.packageId = metadata.packageId
        payload.message = "Đã cài mới '\(metadata.name)' (\(metadata.packageId)) — \(changes.count) file"
        reply(to: envelope, payload: payload)
    }

    private func handleDraftRollback(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId else {
            replyError(to: envelope, code: .malformedMessage, message: "Thiếu packageId")
            return
        }
        let installed = installedExtensions()
        guard let snapshot = installed.first(where: { $0.packageId == packageId }) else {
            replyError(
                to: envelope,
                code: .unknownExtension,
                message: Self.unknownExtensionMessage(requested: packageId, installed: installed)
            )
            return
        }
        // Hai đường rollback, vì `draft.install` có hai đường vào:
        // - **ghi đè** ⇒ có backup ⇒ rollback = trả lại bản cũ;
        // - **cài mới** ⇒ không có backup ⇒ rollback = **tháo hẳn** hàng vừa cài.
        //
        // Trước 1.3.348 chỉ có nhánh đầu, nên `draft.install` (cài mới) tạo được một hàng thư viện mà
        // giao thức **không có cách nào tháo ra** — đo bằng client thật: cài mới thành công rồi
        // `draft.rollback` trả `DRAFT_MISSING`, extension nằm lại trong app phải xoá tay.
        //
        // Điều kiện tháo là **dấu do chính luồng debug ghi**, không phải "không có backup": extension
        // người dùng tự cài từ kho cũng không có backup, suy như vậy là biến công cụ debug thành đường
        // xoá dữ liệu người dùng.
        let hasBackup = await ExtensionDraftInstaller.shared.hasBackup(packageId: packageId)
        let isDebugNewInstall = await ExtensionDraftInstaller.shared.isDebugNewInstall(packageId: packageId)
        guard hasBackup || isDebugNewInstall else {
            replyError(
                to: envelope,
                code: .draftMissing,
                message: "Không có bản sao lưu để rollback, và hàng này không do debug cài mới trong phiên hiện tại"
            )
            return
        }
        let request = ExtensionDebugInstallGate.Request(
            kind: .rollback,
            packageId: packageId,
            revision: hasBackup ? "backup" : "uninstall",
            changes: [
                hasBackup
                    ? "↩ trả lại bản đã sao lưu trước lần cài gần nhất"
                    : "🗑 tháo hẳn bản debug vừa cài mới (xoá file + hàng thư viện)"
            ]
        )
        guard await ExtensionDebugInstallGate.shared.requestApproval(request) == .approved else {
            replyError(to: envelope, code: .approvalRequired, message: "Người dùng không xác nhận trên thiết bị")
            return
        }

        guard hasBackup else {
            do {
                try await ExtensionDraftInstaller.shared.uninstallNewInstall(packageId: packageId)
            } catch {
                replyError(to: envelope, code: .internalError, message: error.localizedDescription)
                return
            }
            if let failure = await deleteLibraryRow(packageId: packageId) {
                replyError(
                    to: envelope,
                    code: .internalError,
                    message: "Đã xoá file nhưng không xoá được hàng thư viện: \(failure)"
                )
                return
            }
            var payload = ExtensionDebugProtocol.Payload()
            payload.packageId = packageId
            payload.message = "Đã tháo '\(packageId)' khỏi thư viện"
            reply(to: envelope, payload: payload)
            return
        }

        do {
            try await ExtensionDraftInstaller.shared.rollback(installedPath: snapshot.localPath, packageId: packageId)
            reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
        } catch {
            replyError(to: envelope, code: .internalError, message: error.localizedDescription)
        }
    }

    /// Xoá hàng `Extension` của một bản do debug cài mới. Trả `nil` khi thành công.
    ///
    /// Cùng khuôn `writeLibraryRow`: `ModelContext` dựng mới từ container (ghi từ tác vụ nền), hop sang
    /// `@MainActor` cho coordinator, và phát `"extensionDidUpdate"` để màn Khám Phá thấy ngay.
    private func deleteLibraryRow(packageId: String) async -> String? {
        let container = self.container
        return await MainActor.run(resultType: String?.self) {
            let result = ExtensionTransactionCoordinator.shared.deleteExtension(
                packageId: packageId,
                in: ModelContext(container)
            )
            switch result {
            case .success:
                NotificationCenter.default.post(name: Notification.Name("extensionDidUpdate"), object: nil)
                return nil
            case .failure(let error):
                return error.localizedDescription
            }
        }
    }

    /// Ghi hàng `Extension` cho bản vừa cài mới. Trả `nil` khi thành công, câu lỗi khi thất bại.
    ///
    /// `ModelContext` được dựng **mới** từ container thay vì dùng context của MainActor — đây là ghi từ
    /// tác vụ nền, đúng luật của repo. Coordinator là `@MainActor` nên vẫn phải hop; chỉ một `String?`
    /// băng qua ranh giới isolation. `"extensionDidUpdate"` phát cùng nhịp với đường restore backup
    /// (`BackupRestoreWorker`) để màn Khám Phá thấy extension mới mà không cần mở lại app.
    private func writeLibraryRow(metadata: ExtensionDraftMetadata, localPath: String) async -> String? {
        let command = metadata.upsertCommand(localPath: localPath)
        let container = self.container
        return await MainActor.run(resultType: String?.self) {
            let result = ExtensionTransactionCoordinator.shared.upsertExtension(
                command: command,
                in: ModelContext(container)
            )
            switch result {
            case .success:
                NotificationCenter.default.post(name: Notification.Name("extensionDidUpdate"), object: nil)
                return nil
            case .failure(let error):
                return error.localizedDescription
            }
        }
    }

    private func replyIssues(
        to envelope: ExtensionDebugProtocol.Envelope,
        code: ExtensionDebugProtocol.ErrorCode,
        issues: [String]
    ) {
        var payload = ExtensionDebugProtocol.Payload()
        payload.code = code.rawValue
        payload.message = issues.first ?? "Bản nháp không hợp lệ"
        payload.issues = issues
        emit(ExtensionDebugProtocol.Envelope(requestId: envelope.requestId, type: "error", payload: payload))
    }
}
