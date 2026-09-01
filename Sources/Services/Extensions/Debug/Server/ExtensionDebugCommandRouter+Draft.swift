import Foundation

/// Nhánh `draft.*` của router: nạp snapshot nháp (Phase 3), cài và rollback (Phase 4).
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
        guard installedExtensions().contains(where: { $0.packageId == manifest.packageId }) else {
            replyError(to: envelope, code: .unknownExtension, message: "packageId chưa được cài trên app")
            return
        }
        let issues = await ExtensionDraftStagingStore.shared.beginStage(manifest)
        guard issues.isEmpty else {
            replyIssues(to: envelope, code: .draftInvalid, issues: issues)
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
            replyError(to: envelope, code: .malformedMessage, message: "Thiếu packageId hoặc revision")
            return
        }
        await ExtensionDraftStagingStore.shared.discard(packageId: packageId, revision: revision)
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    // MARK: - Phase 4

    private func handleDraftInstall(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId,
              let revision = envelope.payload?.sourceRevision,
              let snapshot = installedExtensions().first(where: { $0.packageId == packageId }) else {
            replyError(to: envelope, code: .unknownExtension, message: "Thiếu packageId/revision hoặc extension chưa cài")
            return
        }
        guard await ExtensionDraftStagingStore.shared.hasDraft(packageId: packageId, revision: revision),
              let directory = await ExtensionDraftStagingStore.shared.draftDirectory(packageId: packageId, revision: revision) else {
            replyError(to: envelope, code: .draftMissing, message: "Chưa có bản nháp đã validate")
            return
        }

        let changes = await ExtensionDraftInstaller.shared.changeSummary(
            draftDirectory: directory,
            installedPath: snapshot.localPath
        )
        let request = ExtensionDebugInstallGate.Request(
            kind: .install,
            packageId: packageId,
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
                packageId: packageId
            )
            var payload = ExtensionDebugProtocol.Payload()
            payload.message = "Đã cài \(changes.count) thay đổi; bản cũ được giữ để rollback"
            reply(to: envelope, payload: payload)
        } catch {
            replyError(to: envelope, code: .internalError, message: error.localizedDescription)
        }
    }

    private func handleDraftRollback(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId,
              let snapshot = installedExtensions().first(where: { $0.packageId == packageId }) else {
            replyError(to: envelope, code: .unknownExtension, message: "Thiếu packageId hoặc extension chưa cài")
            return
        }
        guard await ExtensionDraftInstaller.shared.hasBackup(packageId: packageId) else {
            replyError(to: envelope, code: .draftMissing, message: "Không có bản sao lưu để rollback")
            return
        }
        let request = ExtensionDebugInstallGate.Request(
            kind: .rollback,
            packageId: packageId,
            revision: "backup",
            changes: ["↩ trả lại bản đã sao lưu trước lần cài gần nhất"]
        )
        guard await ExtensionDebugInstallGate.shared.requestApproval(request) == .approved else {
            replyError(to: envelope, code: .approvalRequired, message: "Người dùng không xác nhận trên thiết bị")
            return
        }
        do {
            try await ExtensionDraftInstaller.shared.rollback(installedPath: snapshot.localPath, packageId: packageId)
            reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
        } catch {
            replyError(to: envelope, code: .internalError, message: error.localizedDescription)
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
