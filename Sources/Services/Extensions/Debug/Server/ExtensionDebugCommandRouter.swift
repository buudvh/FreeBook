import Foundation
import SwiftData

/// Router lệnh của debug server.
///
/// Từ 1.3.305 **không còn cửa pairing**: bật server là client nối được, đúng như một server API trên
/// LAN. Hai chốt còn lại vẫn là chốt thật:
/// 1. Server tự resolve script qua manifest của extension đã chọn — `run.start` chỉ nhận `packageId` +
///    `entrypoint` + input, **không** có field path, không `eval`, không source raw.
/// 2. Mọi lệnh ghi đè dữ liệu người dùng (`draft.install`, `draft.rollback`) vẫn phải đi qua
///    `ExtensionDebugInstallGate`, tức phải bấm trên thiết bị.
public actor ExtensionDebugCommandRouter {
    private let container: ModelContainer
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

    /// Trả về tên client nếu message này khai báo tên (`hello`), để server hiện lên UI.
    @discardableResult
    public func handle(_ data: Data) async -> String? {
        guard let envelope = try? JSONDecoder().decode(ExtensionDebugProtocol.Envelope.self, from: data) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: "-", code: .malformedMessage, message: "Không parse được message"))
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
                scripts: snapshot.scriptKeys
            )
        }
        reply(to: envelope, payload: payload)
    }

    private func handleRunStart(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let packageId = envelope.payload?.packageId,
              let snapshot = installedExtensions().first(where: { $0.packageId == packageId }) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownExtension, message: "Không có extension này"))
            return
        }
        guard let entrypoint = Self.entrypoint(from: envelope.payload) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownEntrypoint, message: "Entrypoint không hợp lệ"))
            return
        }

        var localPath = snapshot.localPath
        if envelope.payload?.sourceMode == "draft" {
            guard let revision = envelope.payload?.sourceRevision,
                  await ExtensionDraftStagingStore.shared.hasDraft(packageId: packageId, revision: revision),
                  let draftDirectory = await ExtensionDraftStagingStore.shared.draftDirectory(packageId: packageId, revision: revision) else {
                emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .draftMissing, message: "Chưa có bản nháp đã validate cho revision này"))
                return
            }
            localPath = draftDirectory.path
        }

        let runId = await runner.start(
            packageId: packageId,
            localPath: localPath,
            downloadUrl: snapshot.downloadUrl,
            configJson: snapshot.configJson,
            host: snapshot.sourceUrl,
            entrypoint: entrypoint
        )
        var payload = ExtensionDebugProtocol.Payload()
        payload.runId = runId.uuidString
        reply(to: envelope, payload: payload)
    }

    private func handleRunCancel(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let raw = envelope.payload?.runId, let runId = UUID(uuidString: raw) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownRun, message: "runId không hợp lệ"))
            return
        }
        await runner.cancel(runId: runId)
        reply(to: envelope, payload: ExtensionDebugProtocol.Payload())
    }

    private func handleRunGet(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let raw = envelope.payload?.runId, let runId = UUID(uuidString: raw) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .unknownRun, message: "runId không hợp lệ"))
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

    private static func entrypoint(from payload: ExtensionDebugProtocol.Payload?) -> ExtensionDebugEntrypoint? {
        guard let payload, let name = payload.entrypoint else { return nil }
        switch name {
        case "search":
            guard let keyword = payload.keyword else { return nil }
            return .search(keyword: keyword, page: payload.page ?? 1)
        case "detail":
            guard let url = payload.url else { return nil }
            return .detail(url: url)
        case "toc":
            guard let url = payload.url else { return nil }
            return .toc(url: url)
        case "chap":
            guard let url = payload.url else { return nil }
            return .chap(url: url)
        case "genre":
            return .genre
        case "home":
            return .home
        case "custom":
            guard let fileName = payload.scriptFileName else { return nil }
            return .custom(
                fileName: fileName,
                input: payload.input ?? "",
                page: payload.page ?? 1,
                pageUrl: payload.pageUrl
            )
        default:
            return nil
        }
    }
}
