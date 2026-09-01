import Foundation
import SwiftData

/// Router lệnh của debug server: nơi **duy nhất** cưỡng chế "chưa pair thì không được list/run/stage".
///
/// Hai luật của Phase 0 nằm ở đây:
/// 1. Chỉ `hello` và `pair` được phép trước khi pair. Mọi lệnh khác trả `NOT_PAIRED`.
/// 2. Server tự resolve script qua manifest của extension đã chọn. **Không** nhận `localPath`,
///    filename tuỳ ý hay source JavaScript raw trong `run.start` — đó là lý do payload chỉ có
///    `packageId` + `entrypoint` + input, không có field path nào.
public actor ExtensionDebugCommandRouter {
    private let container: ModelContainer
    private let pairing: ExtensionDebugPairingAuthority
    private let hub: ExtensionDebugEventHub
    private let runner: ExtensionDebugRunner
    private let staging: ExtensionDraftStagingStore
    private let installer: ExtensionDraftInstaller
    private let gate: ExtensionDebugInstallGate

    /// Kênh gửi ra client, do server bơm vào. Router không giữ `NWConnection`.
    private var send: (@Sendable (ExtensionDebugProtocol.Envelope) -> Void)?
    private var eventForwardTask: Task<Void, Never>?

    public init(
        container: ModelContainer,
        pairing: ExtensionDebugPairingAuthority,
        hub: ExtensionDebugEventHub = .shared,
        runner: ExtensionDebugRunner = .shared,
        staging: ExtensionDraftStagingStore = .shared,
        installer: ExtensionDraftInstaller = .shared,
        gate: ExtensionDebugInstallGate = .shared
    ) {
        self.container = container
        self.pairing = pairing
        self.hub = hub
        self.runner = runner
        self.staging = staging
        self.installer = installer
        self.gate = gate
    }

    public func attach(send: @escaping @Sendable (ExtensionDebugProtocol.Envelope) -> Void) {
        self.send = send
    }

    public func detach() {
        eventForwardTask?.cancel()
        eventForwardTask = nil
        send = nil
    }

    public func handle(_ data: Data) async {
        guard let envelope = try? JSONDecoder().decode(ExtensionDebugProtocol.Envelope.self, from: data) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: "-", code: .malformedMessage, message: "Không parse được message"))
            return
        }
        guard envelope.version == ExtensionDebugProtocol.version else {
            emit(ExtensionDebugProtocol.errorEnvelope(
                requestId: envelope.requestId,
                code: .unsupportedVersion,
                message: "Server nói version \(ExtensionDebugProtocol.version)"
            ))
            return
        }
        guard let type = ExtensionDebugProtocol.CommandType(rawValue: envelope.type) else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .malformedMessage, message: "Lệnh '\(envelope.type)' không có"))
            return
        }

        switch type {
        case .hello:
            await handleHello(envelope)
        case .pair:
            await handlePair(envelope)
        default:
            guard await pairing.isPaired else {
                emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .notPaired, message: "Chưa ghép nối"))
                return
            }
            await handlePaired(type, envelope)
        }
    }

    private func handlePaired(_ type: ExtensionDebugProtocol.CommandType, _ envelope: ExtensionDebugProtocol.Envelope) async {
        switch type {
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
        case .hello, .pair:
            break
        }
    }

    // MARK: - hello / pair

    private func handleHello(_ envelope: ExtensionDebugProtocol.Envelope) async {
        var payload = ExtensionDebugProtocol.Payload()
        payload.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        payload.contractVersion = ExtensionDebugEvent.contractVersion
        payload.requiresPairing = !(await pairing.isPaired)
        reply(to: envelope, payload: payload)
    }

    private func handlePair(_ envelope: ExtensionDebugProtocol.Envelope) async {
        guard let token = envelope.payload?.token, !token.isEmpty else {
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: .malformedMessage, message: "Thiếu token"))
            return
        }
        let clientName = envelope.payload?.clientName ?? "Máy phát triển"
        switch await pairing.requestPairing(token: token, clientName: clientName) {
        case .failure(let code):
            emit(ExtensionDebugProtocol.errorEnvelope(requestId: envelope.requestId, code: code, message: "Ghép nối bị từ chối"))
        case .success:
            var payload = ExtensionDebugProtocol.Payload()
            payload.message = "Chờ người dùng xác nhận trên thiết bị"
            reply(to: envelope, payload: payload)
        }
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
                  await staging.hasDraft(packageId: packageId, revision: revision),
                  let draftDirectory = await staging.draftDirectory(packageId: packageId, revision: revision) else {
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
