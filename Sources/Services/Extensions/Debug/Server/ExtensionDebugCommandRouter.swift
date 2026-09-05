import Foundation
import SwiftData

/// Router lệnh của debug server.
///
/// Từ 1.3.305 **không còn cửa pairing**: bật server là client nối được, đúng như một server API trên
/// LAN. Hai chốt còn lại vẫn là chốt thật:
/// 1. Server tự resolve script qua manifest của extension đã chọn — `run.start` chỉ nhận `packageId` +
///    `entrypoint` + input, **không** có field path, không `eval`, không source raw.
/// 2. Mọi lệnh ghi vào dữ liệu người dùng (`draft.install` — cả nhánh ghi đè lẫn nhánh **cài mới** —
///    và `draft.rollback`) vẫn phải đi qua `ExtensionDebugInstallGate`, tức phải bấm trên thiết bị.
///
/// Từ 1.3.325 `draft.install` có hai nhánh: extension đã có trên app thì **ghi đè** file (metadata thư
/// viện không đổi), chưa có thì **cài mới** — dựng `extensions/<packageId>/` rồi thêm hàng `Extension`
/// qua `ExtensionTransactionCoordinator`. Đây là chỗ duy nhất trong phân hệ debug ghi SwiftData, và nó
/// ghi bằng `ModelContext` riêng dựng từ `container`.
public actor ExtensionDebugCommandRouter {
    /// `internal` chứ không `private`: nhánh `draft.*` nằm ở file `+Draft.swift`, mà `private` trong
    /// Swift là phạm vi **file** — đường cài mới cần container để dựng `ModelContext` riêng.
    internal let container: ModelContainer
    private let hub: ExtensionDebugEventHub
    private let runner: ExtensionDebugRunner

    /// Kênh gửi ra client, do server bơm vào. Router không giữ `NWConnection`.
    private var send: (@Sendable (ExtensionDebugProtocol.Envelope) -> Void)?
    private var eventForwardTask: Task<Void, Never>?

    public init(
        container: ModelContainer,
        hub: ExtensionDebugEventHub = .shared,
        runner: ExtensionDebugRunner = .shared
    ) {
        self.container = container
        self.hub = hub
        self.runner = runner
    }

    public func attach(send: @escaping @Sendable (ExtensionDebugProtocol.Envelope) -> Void) {
        self.send = send
    }

    public func detach() {
        eventForwardTask?.cancel()
        eventForwardTask = nil
        send = nil
    }

    /// Chỉ đủ để vớt `requestId` khi `Envelope` không decode được — xem `handle(_:)`.
    private struct EnvelopeHeader: Decodable {
        let requestId: String?
        let type: String?
    }

    /// Trả về tên client nếu message này khai báo tên (`hello`), để server hiện lên UI.
    @discardableResult
    public func handle(_ data: Data) async -> String? {
        guard let envelope = try? JSONDecoder().decode(ExtensionDebugProtocol.Envelope.self, from: data) else {
            // Ca hay gặp nhất **không** phải JSON rác mà là envelope đúng dạng với `payload` sai shape
            // (client đang viết dở, ví dụ `manifest` thiếu field). Trước 1.3.345 chỗ này luôn trả
            // `requestId: "-"`, nên client không ghép được lỗi vào request nào và cứ **treo tới hết
            // timeout** — đo được: `draft.stage` với manifest sai field không nhận reply nào trong 20 s.
            // Vớt lấy `requestId` bằng một lượt decode tối thiểu để client fail ngay và biết vì sao.
            let header = try? JSONDecoder().decode(EnvelopeHeader.self, from: data)
            let message = header?.type.map { "Payload của lệnh '\($0)' không đúng dạng" }
                ?? "Không parse được message"
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: header?.requestId ?? "-",
                code: .malformedMessage,
                message: message
            ))
            return nil
        }
        guard envelope.version == ExtensionDebugProtocol.version else {
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unsupportedVersion,
                message: "Server nói version \(ExtensionDebugProtocol.version)"
            ))
            return nil
        }
        guard let type = ExtensionDebugProtocol.CommandType(rawValue: envelope.type) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .malformedMessage, message: "Lệnh '\(envelope.type)' không có"))
            return nil
        }

        switch type {
        case .hello:
            handleHello(envelope)
            return envelope.payload?.clientName
        case .extensionsList:
            handleExtensionsList(envelope)
        case .runStart:
            await handleRunStart(envelope)
        case .runCancel:
            await handleRunCancel(envelope)
        case .runGet:
            await handleRunGet(envelope)
        case .eventsSubscribe:
            handleEventsSubscribe(envelope)
        case .draftStage, .draftChunk, .draftFinish, .draftDiscard, .draftInstall, .draftRollback:
            await handleDraft(type, envelope)
        }
        return nil
    }

    // MARK: - hello

    private func handleHello(_ envelope: ExtensionDebugProtocol.Envelope) {
        var payload = ExtensionDebugProtocol.Payload()
        payload.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        payload.contractVersion = ExtensionDebugEvent.contractVersion
        reply(to: envelope, payload: payload)
    }

    // MARK: - extensions / run

    private func handleExtensionsList(_ envelope: ExtensionDebugProtocol.Envelope) {
        var payload = ExtensionDebugProtocol.Payload()
        payload.extensions = installedExtensions().map { snapshot in
            ExtensionDebugProtocol.ExtensionInfo(
                packageId: snapshot.packageId,
                name: snapshot.name,
                version: snapshot.version,
                type: snapshot.type,
                scripts: snapshot.scriptKeys,
                executableScripts: snapshot.executableScripts
            )
        }
        reply(to: envelope, payload: payload)
    }

    private func handleRunStart(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .malformedMessage, message: "Thiếu packageId"))
            return
        }
        // Ba ca tách rõ: tên lạ, thiếu tham số, và hợp lệ. Gộp hai ca đầu thành `UNKNOWN_ENTRYPOINT`
        // như trước 1.3.347 đẩy người viết client đi kiểm danh sách script trong khi lỗi ở payload —
        // đo được: `entrypoint: "search"` không kèm `keyword` báo `UNKNOWN_ENTRYPOINT`.
        let entrypoint: ExtensionDebugEntrypoint
        switch ExtensionDebugEntrypointResolver.resolve(from: envelope.payload) {
        case .resolved(let resolved):
            entrypoint = resolved
        case .unknownName(let name):
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unknownEntrypoint,
                message: "Entrypoint '\(name ?? "(thiếu)")' không có. Được phép: \(ExtensionDebugEntrypointResolver.allowedNames.joined(separator: ", "))"
            ))
            return
        case .missingArgument(let name, let field):
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .malformedMessage,
                message: "Entrypoint '\(name)' thiếu tham số '\(field)'"
            ))
            return
        }
        let installed = installedExtensions()
        let snapshot = installed.first(where: { $0.packageId == packageId })

        // `sourceMode: "draft"` chạy thẳng từ thư mục staging và **không** đòi extension đã cài: đó là
        // cách thử một extension mới trước khi quyết định thêm nó vào thư viện. Metadata còn thiếu được
        // đọc từ `plugin.json` của chính bản nháp; `configJson` rỗng vẫn hợp lệ vì
        // `ExtensionManager.getCombinedConfigs` lấy mặc định từ khoá `config` trong `plugin.json`.
        if envelope.payload?.sourceMode == "draft" {
            guard let revision = envelope.payload?.sourceRevision,
                  await ExtensionDraftStagingStore.shared.hasDraft(packageId: packageId, revision: revision),
                  let draftDirectory = await ExtensionDraftStagingStore.shared.draftDirectory(packageId: packageId, revision: revision) else {
                emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .draftMissing, message: "Chưa có bản nháp đã validate cho revision này"))
                return
            }
            let draftMetadata = try? ExtensionDraftMetadata.read(from: draftDirectory)
            await startRun(
                envelope,
                packageId: packageId,
                localPath: draftDirectory.path,
                downloadUrl: snapshot?.downloadUrl ?? "",
                configJson: snapshot?.configJson ?? "",
                host: snapshot?.sourceUrl ?? draftMetadata?.sourceUrl,
                entrypoint: entrypoint
            )
            return
        }

        guard let snapshot else {
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unknownExtension,
                message: Self.unknownExtensionMessage(requested: packageId, installed: installed)
            ))
            return
        }
        await startRun(
            envelope,
            packageId: packageId,
            localPath: snapshot.localPath,
            downloadUrl: snapshot.downloadUrl,
            configJson: snapshot.configJson,
            host: snapshot.sourceUrl,
            entrypoint: entrypoint
        )
    }

    /// Một chỗ duy nhất phát `run.start` cho cả hai nguồn (bản đã cài / thư mục nháp), để hai đường
    /// không bao giờ lệch nhau về những gì được truyền vào runner.
    private func startRun(
        _ envelope: ExtensionDebugProtocol.Envelope,
        packageId: String,
        localPath: String,
        downloadUrl: String,
        configJson: String,
        host: String?,
        entrypoint: ExtensionDebugEntrypoint
    ) async {
        let runId = await runner.start(
            packageId: packageId,
            localPath: localPath,
            downloadUrl: downloadUrl,
            configJson: configJson,
            host: host,
            entrypoint: entrypoint
        )
        var payload = ExtensionDebugProtocol.Payload()
        payload.runId = runId.uuidString
        reply(to: envelope, payload: payload)
    }

    /// Huỷ một run. `UNKNOWN_RUN` khi id **chưa từng** là run nào — run đã kết thúc thì vẫn trả thành
    /// công, vì "huỷ cái đã xong" là no-op hợp lệ, không phải lỗi của client.
    private func handleRunCancel(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let raw = envelope.payload?.runId, let runId = UUID(uuidString: raw) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownRun, message: "runId không hợp lệ"))
            return
        }
        let isActive = await runner.activeRunIds.contains(runId)
        // Hai `await` phải nằm ở hai `let` riêng: Swift không cho `await` bên phải `||` (toán hạng thứ
        // hai là autoclosure không hỗ trợ concurrency). Không short-circuit cũng không sao — cả hai
        // đều là một lượt đọc actor.
        let isKnown = await hub.hasRun(runId)
        guard isActive || isKnown else {
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unknownRun,
                message: "Không có run \(raw)"
            ))
            return
        }
        await runner.cancel(runId: runId)
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    /// Lấy event của một run.
    ///
    /// Phải phân biệt **run không tồn tại** với **run có thật mà chưa có event**: trước 1.3.344 cả hai
    /// đều trả `events: []`, `droppedCount: 0` nên client không có cách nào biết mình gửi sai id — đo
    /// bằng client thật: một `runId` bịa ra cũng nhận reply thành công. `ErrorCode.unknownRun` đã khai
    /// sẵn cho đúng ca này mà chưa chỗ nào phát.
    private func handleRunGet(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let raw = envelope.payload?.runId, let runId = UUID(uuidString: raw) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownRun, message: "runId không hợp lệ"))
            return
        }
        let isActive = await runner.activeRunIds.contains(runId)
        let isKnown = await hub.hasRun(runId)
        guard isActive || isKnown else {
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unknownRun,
                message: "Không có run \(raw) — có thể đã bị đẩy khỏi buffer event."
            ))
            return
        }
        var payload = ExtensionDebugProtocol.Payload()
        payload.runId = raw
        payload.events = await hub.events(for: runId)
        payload.droppedCount = await hub.droppedCount(for: runId)
        reply(to: envelope, payload: payload)
    }

    /// Một subscription duy nhất, phát **mọi** run. Client tự lọc theo `runId` — rẻ hơn là giữ nhiều
    /// stream, và client vốn chỉ chạy một run tại một thời điểm.
    private func handleEventsSubscribe(_ envelope: ExtensionDebugProtocol.Envelope) {
        eventForwardTask?.cancel()
        let subscriptionId = envelope.requestId
        eventForwardTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.hub.stream()
            for await event in stream {
                await self.forward(event: event, subscriptionId: subscriptionId)
            }
        }
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    private func forward(event: ExtensionDebugEvent, subscriptionId: String) {
        var payload = ExtensionDebugProtocol.Payload()
        payload.events = [event]
        emit(ExtensionDebugProtocol.Envelope(requestId: subscriptionId, type: "event", payload: payload))
    }

    // MARK: - Helpers

    internal func emit(_ envelope: ExtensionDebugProtocol.Envelope) {
        send?(envelope)
    }

    internal func reply(to envelope: ExtensionDebugProtocol.Envelope, payload: ExtensionDebugProtocol.Payload) {
        emit(ExtensionDebugProtocol.Envelope(requestId: envelope.requestId, type: "reply", payload: payload))
    }

    internal func replyError(to envelope: ExtensionDebugProtocol.Envelope, code: ExtensionDebugProtocol.ErrorCode, message: String) {
        emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: code, message: message))
    }

    /// Đọc SwiftData bằng `ModelContext` **riêng** dựng từ container — luật của repo cho tác vụ nền.
    /// Trả snapshot bất biến, không trả `@Model` ra khỏi context.
    internal func installedExtensions() -> [ExtensionDebugInstalledSnapshot] {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<Extension>()
        guard let rows = try? context.fetch(descriptor) else { return [] }
        return rows
            .filter { !$0.localPath.isEmpty }
            .map { ExtensionDebugInstalledSnapshot(extensionRow: $0) }
    }

    /// Lỗi `UNKNOWN_EXTENSION` phải nói ra app đang có id nào.
    ///
    /// Client suy `packageId` từ `plugin.json`, còn app sinh id theo **ba** luật khác nhau tuỳ đường
    /// cài: repo sync dùng `name.lowercased()` + thay dấu cách bằng `_`
    /// (`ExtensionSyncCommandBuilder.packageId(forName:)`), import zip dùng `metadata.packageId` hoặc
    /// `name.lowercased()` **không** thay dấu cách, restore backup giữ nguyên id đã lưu. Vì vậy lệch id
    /// là lỗi thường gặp nhất của phân hệ này, và một câu "Không có extension này" trơ trọi không cho
    /// người dùng đường nào để tự sửa. Liệt kê id **không lộ gì mới**: `extensions.list` vốn đã trả
    /// đúng những id đó cho cùng client.
    internal static func unknownExtensionMessage(
        requested: String?,
        installed: [ExtensionDebugInstalledSnapshot]
    ) -> String {
        let ids = installed.map(\.packageId).sorted()
        let list = ids.isEmpty ? "(app chưa cài extension nào)" : ids.joined(separator: ", ")
        return "Không có extension '\(requested ?? "-")'. App đang có: \(list)"
    }
}
