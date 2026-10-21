import Foundation

/// Nhánh `legado.*` của router (protocol v2): liệt kê nguồn Legado chữ, bắt đầu / xem / huỷ lượt nghiệm thu
/// (`LegadoCorpusRunner`).
///
/// Chốt an toàn của nhánh này:
/// - **Đầu vào hẹp** (rules.md, debug server 1.3.303 #2): `packageIds` **hoặc** `allEnabled`, `keyword` (từ khoá tìm kiếm
///   thuần — URL và tiền tố `++`/`--`/`::` bị từ chối), `limit`, `includeSources`, `runId`. Không URL, path hay JS từ
///   client; tiền tố gỡ lỗi chỉ được đọc từ `checkKeyWord` trong `source.json` của chính nguồn.
/// - **Không qua `ExtensionDebugInstallGate`**: lệnh không ghi thư viện tiện ích, sách, cài đặt hay file nguồn — chỉ ghi
///   `applicationSupport/legado_reports/`, cùng trạng thái engine mà một lượt duyệt nguồn thường cũng ghi (cookie, biến/
///   cache nguồn); trạng thái truyện dùng `bookId` có namespace `corpus-runner:<packageId>`, không trùng sách thật. Gate
///   dành cho lệnh ghi đè dữ liệu người dùng; mượn `Kind` cũ cho việc khác là làm người bấm hiểu sai (rules.md 1.3.325).
/// - Không còn cổng ghép đôi từ 1.3.305: lệnh đi qua `handle(_:)` như mọi lệnh khác.
/// - Báo cáo trả về là kiểu có khai báo (`LegadoCorpusReport`), đã redact từ lúc tạo: không nội dung chương, cookie,
///   header hay thân phản hồi.
extension ExtensionDebugCommandRouter {
    internal func handleLegado(
        _ type: ExtensionDebugProtocol.CommandType,
        _ envelope: ExtensionDebugProtocol.Envelope
    ) async {
        guard envelope.version >= ExtensionDebugProtocol.legadoCommandsMinimumVersion else {
            replyError(
                to: envelope,
                code: .unsupportedVersion,
                message: "Lệnh '\(type.rawValue)' cần protocol v\(ExtensionDebugProtocol.legadoCommandsMinimumVersion) — cập nhật client VS Code"
            )
            return
        }
        switch type {
        case .legadoSources:
            await handleLegadoSources(envelope)
        case .legadoCorpusStart:
            await handleLegadoCorpusStart(envelope)
        case .legadoCorpusStatus:
            await handleLegadoCorpusStatus(envelope)
        case .legadoCorpusCancel:
            await handleLegadoCorpusCancel(envelope)
        default:
            break
        }
    }

    /// `run.start` không chạy được nguồn Legado (không có `search.js`/`detail.js`…). `nil` = cho đi tiếp.
    /// `sourceMode: "draft"` chạy thư mục nháp JS nên không áp.
    internal static func legadoRunRejection(packageId: String, sourceMode: String?) -> String? {
        guard sourceMode != "draft",
              let row = ExtensionLibraryRepository.snapshot(packageId: packageId),
              LegadoSourceIdentity.isLegado(row) else {
            return nil
        }
        return "'\(packageId)' là nguồn Legado — không có script JS cho run.start. "
            + "Dùng legado.corpus.start (VS Code: FreeBook: Chạy nghiệm thu nguồn Legado)."
    }

    // MARK: - Lệnh

    private func handleLegadoSources(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let sources = await LegadoCorpusRunner.availableSources() else {
            replyError(to: envelope, code: .internalError, message: LegadoCorpusRunner.StartError.snapshotNotReady.message)
            return
        }
        let enabledCount = sources.filter { $0.enabled }.count
        var payload = ExtensionDebugProtocol.Payload()
        payload.legadoSources = sources
        payload.message = "\(sources.count) nguồn Legado chữ, \(enabledCount) đang bật"
        reply(to: envelope, payload: payload)
    }

    private func handleLegadoCorpusStart(_ envelope: ExtensionDebugProtocol.Envelope) async {
        let input = envelope.payload
        let request: LegadoCorpusRequest
        switch LegadoCorpusRequest.make(
            packageIds: input?.packageIds,
            allEnabled: input?.allEnabled,
            keyword: input?.keyword,
            limit: input?.limit
        ) {
        case .success(let made):
            request = made
        case .failure(let issue):
            replyError(to: envelope, code: .malformedMessage, message: issue.message)
            return
        }

        do {
            let status = try await LegadoCorpusRunner.shared.start(request)
            var payload = ExtensionDebugProtocol.Payload()
            payload.runId = status.runId
            payload.legadoCorpus = status
            payload.message = "Đã bắt đầu: \(status.totalSources - status.skipped) nguồn chạy, \(status.skipped) bỏ qua"
            reply(to: envelope, payload: payload)
        } catch let error as LegadoCorpusRunner.StartError {
            let code: ExtensionDebugProtocol.ErrorCode
            switch error {
            case .busy:
                code = .busy
            case .snapshotNotReady:
                code = .internalError
            case .noSources:
                code = .unknownExtension
            }
            replyError(to: envelope, code: code, message: error.message)
        } catch {
            replyError(to: envelope, code: .internalError, message: ExtensionDebugRedactor.message(error.localizedDescription))
        }
    }

    private func handleLegadoCorpusStatus(_ envelope: ExtensionDebugProtocol.Envelope) async {
        let includeSources = envelope.payload?.includeSources ?? false
        guard let status = await LegadoCorpusRunner.shared.status(includeSources: includeSources) else {
            var payload = ExtensionDebugProtocol.Payload()
            payload.message = "Chưa có lượt nghiệm thu nào trong phiên app này"
            reply(to: envelope, payload: payload)
            return
        }
        if let requested = envelope.payload?.runId, requested != status.runId {
            replyError(
                to: envelope,
                code: .unknownRun,
                message: "Không có lượt \(requested) — lượt gần nhất là \(status.runId)"
            )
            return
        }
        var payload = ExtensionDebugProtocol.Payload()
        payload.runId = status.runId
        payload.legadoCorpus = status
        payload.message = "\(status.state.rawValue): \(status.completed)/\(status.totalSources) nguồn · qua "
            + "\(status.passed)/\(status.attempted) (\(status.passPercent)%)"
        reply(to: envelope, payload: payload)
    }

    private func handleLegadoCorpusCancel(_ envelope: ExtensionDebugProtocol.Envelope) async {
        let requested = envelope.payload?.runId
        let outcome = await LegadoCorpusRunner.shared.cancel(runId: requested)
        var payload = ExtensionDebugProtocol.Payload()
        switch outcome {
        case .cancelling(let runId):
            payload.runId = runId
            payload.message = "Đang huỷ lượt \(runId) — báo cáo dở dang sẽ được ghi"
        case .notRunning:
            payload.message = "Không có lượt nào đang chạy"
        case .unknownRun:
            replyError(to: envelope, code: .unknownRun, message: "Không có lượt \(requested ?? "-")")
            return
        }
        reply(to: envelope, payload: payload)
    }
}
