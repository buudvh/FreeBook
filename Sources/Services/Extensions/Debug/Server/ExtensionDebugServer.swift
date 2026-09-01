import Foundation
import Network
import SwiftData

/// Debug server trên LAN: `NWListener` + WebSocket + Bonjour, **tối đa một client**, chỉ khi người dùng
/// bật bằng tay và chỉ khi app ở foreground.
///
/// Bốn luật của Phase 0 được cưỡng chế ở đây:
/// 1. **Port ngẫu nhiên** (`.any`) — không có port cố định để dò.
/// 2. **Một client.** Kết nối thứ hai bị `cancel()` ngay, không xếp hàng.
/// 3. **Token trong QR/URI, không trong Bonjour.** `NWListener.Service` không mang TXT record nào.
/// 4. **Tắt là tắt hẳn**: `stop()` gỡ Bonjour, đóng socket, huỷ mọi run đang chạy, nhả mọi waiter của
///    cửa xác nhận, và xoá sạch staging.
public actor ExtensionDebugServer {
    public static let shared = ExtensionDebugServer()

    private let queue = DispatchQueue(label: "com.freebook.extdebug.server")
    private let pairing = ExtensionDebugPairingAuthority()

    private var listener: NWListener?
    private var connection: ExtensionDebugConnection?
    private var router: ExtensionDebugCommandRouter?
    private var status = ExtensionDebugServerStatus()
    private var observers: [UUID: AsyncStream<ExtensionDebugServerStatus>.Continuation] = [:]
    private var currentToken: String?
    private var currentExpiry: Date?
    private var currentServiceName: String = "FreeBook"
    /// Listener hiện tại có đang quảng bá Bonjour hay không. Khác với lựa chọn của người dùng: sau một
    /// lượt fallback, người dùng vẫn bật nhưng listener thì không.
    private var isAdvertisingBonjour = false
    private var didFallbackFromBonjour = false

    public init() {}

    public var currentStatus: ExtensionDebugServerStatus { status }

    public func statusStream() -> AsyncStream<ExtensionDebugServerStatus> {
        let (stream, continuation) = AsyncStream<ExtensionDebugServerStatus>.makeStream()
        let key = UUID()
        observers[key] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(key) }
        }
        return stream
    }

    private func removeObserver(_ key: UUID) {
        observers.removeValue(forKey: key)
    }

    private func publish(_ mutate: (inout ExtensionDebugServerStatus) -> Void) {
        mutate(&status)
        for continuation in observers.values {
            continuation.yield(status)
        }
    }

    // MARK: - Bật / tắt

    /// `advertisesBonjour` mặc định **tắt**. Lý do: Bonjour cần Info.plist/entitlement được hệ thống
    /// cấp cho *chính bundle đang chạy*, mà app này chạy qua LiveContainer nên `NWListener.service`
    /// thường trả `NWError -65555 (NoAuth)` và làm cả listener chuyển sang `.failed` — server chết dù
    /// cổng TCP đã mở xong. Kết nối trực tiếp `ws://<ip>:<port>` không cần Bonjour và là đường chính.
    public func start(container: ModelContainer, serviceName: String, advertisesBonjour: Bool = false) async {
        guard listener == nil else { return }
        publish { $0 = ExtensionDebugServerStatus(phase: .starting) }

        let token = await pairing.issueToken()
        currentToken = token
        currentExpiry = await pairing.currentExpiry
        currentServiceName = serviceName
        didFallbackFromBonjour = false
        router = ExtensionDebugCommandRouter(container: container, pairing: pairing)

        launchListener(withBonjour: advertisesBonjour, note: nil)
    }

    /// Dựng `NWListener` mới. Tách khỏi `start` để lượt fallback (Bonjour thất bại) dùng lại được mà
    /// **không** cấp token mới — người dùng đang nhìn QR không bị đổi mã dưới chân.
    private func launchListener(withBonjour: Bool, note: String?) {
        let parameters = NWParameters.tcp
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        do {
            let newListener = try NWListener(using: parameters)
            if withBonjour {
                newListener.service = NWListener.Service(name: currentServiceName, type: "_freebook-extdebug._tcp")
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleListenerState(state) }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            listener = newListener
            isAdvertisingBonjour = withBonjour
            publish { $0.bonjourNote = note }
            newListener.start(queue: queue)
        } catch {
            publish { $0 = ExtensionDebugServerStatus(phase: .failed, failureMessage: error.localizedDescription) }
            listener = nil
            router = nil
        }
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        connection?.close(reason: "Server đã tắt")
        connection = nil
        await router?.detach()
        router = nil
        currentToken = nil
        currentExpiry = nil
        isAdvertisingBonjour = false
        didFallbackFromBonjour = false
        await pairing.reset()
        await ExtensionDebugRunner.shared.cancelAll()
        await ExtensionDebugInstallGate.shared.cancelPending()
        await ExtensionDraftStagingStore.shared.discardAll()
        publish { $0 = ExtensionDebugServerStatus(phase: .stopped) }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            let port = listener?.port?.rawValue
            let host = ExtensionDebugNetworkAddress.currentIPv4()
            let uri = Self.pairingURI(
                host: host,
                serviceName: currentServiceName,
                port: port,
                token: currentToken ?? ""
            )
            publish {
                $0.phase = .waitingForClient
                $0.port = port
                $0.host = host
                $0.serviceName = isAdvertisingBonjour ? currentServiceName : nil
                $0.pairingURI = uri
                $0.pairingExpiresAt = currentExpiry
                $0.failureMessage = nil
            }
        case .failed(let error):
            // Bonjour là tiện lợi, không phải điều kiện. Đăng ký mDNS thất bại thì dựng lại listener
            // **không** Bonjour thay vì để cả server chết — cổng TCP vốn đã mở được.
            if isAdvertisingBonjour, !didFallbackFromBonjour {
                didFallbackFromBonjour = true
                listener?.cancel()
                listener = nil
                launchListener(
                    withBonjour: false,
                    note: "Bonjour không đăng ký được (\(error.localizedDescription)) — đã chuyển sang kết nối trực tiếp theo IP:port."
                )
                return
            }
            publish {
                $0.phase = .failed
                $0.failureMessage = error.localizedDescription
            }
        case .cancelled:
            publish { $0 = ExtensionDebugServerStatus(phase: .stopped) }
        default:
            break
        }
    }

    // MARK: - Kết nối

    private func accept(_ nwConnection: NWConnection) {
        guard connection == nil, let router else {
            nwConnection.cancel()
            return
        }
        let handler = ExtensionDebugConnection(
            connection: nwConnection,
            queue: queue,
            onMessage: { [weak self] data in
                Task { await self?.route(data) }
            },
            onClose: { [weak self] reason in
                Task { await self?.handleDisconnect(reason: reason) }
            }
        )
        connection = handler
        Task { [weak self] in
            await router.attach(send: { envelope in
                Task { await self?.send(envelope) }
            })
        }
        handler.start()
    }

    private func send(_ envelope: ExtensionDebugProtocol.Envelope) {
        connection?.send(envelope)
    }

    private func route(_ data: Data) async {
        await router?.handle(data)
        let pendingClient = await pairing.currentPendingClient
        let paired = await pairing.isPaired
        publish {
            $0.pendingClientName = pendingClient
            if paired {
                $0.phase = .paired
                $0.pairingURI = nil
            } else if pendingClient != nil {
                $0.phase = .waitingForApproval
            }
        }
    }

    private func handleDisconnect(reason: String?) async {
        connection = nil
        await router?.detach()
        await ExtensionDebugRunner.shared.cancelAll()
        await ExtensionDebugInstallGate.shared.cancelPending()
        guard listener != nil else { return }
        // Client rời đi nhưng server vẫn bật: quay lại chờ, và **cấp token mới** — token cũ coi như đã
        // đi qua mạng nên không dùng lại.
        let token = await pairing.issueToken()
        currentToken = token
        currentExpiry = await pairing.currentExpiry
        let uri = Self.pairingURI(
            host: status.host,
            serviceName: currentServiceName,
            port: status.port,
            token: token
        )
        publish {
            $0.phase = .waitingForClient
            $0.pairedClientName = nil
            $0.pendingClientName = nil
            $0.pairingURI = uri
            $0.pairingExpiresAt = currentExpiry
            $0.failureMessage = reason
        }
    }

    // MARK: - Xác nhận trên thiết bị

    public func approvePairing() async {
        await pairing.approvePending()
        let name = await pairing.currentPairedClient
        publish {
            $0.phase = .paired
            $0.pairedClientName = name
            $0.pendingClientName = nil
            $0.pairingURI = nil
            $0.pairingExpiresAt = nil
        }
        var payload = ExtensionDebugProtocol.Payload()
        payload.message = "Đã được xác nhận trên thiết bị"
        send(ExtensionDebugProtocol.Envelope(requestId: "pairing", type: "paired", payload: payload))
    }

    public func rejectPairing() async {
        await pairing.rejectPending()
        connection?.close(reason: "Người dùng từ chối ghép nối")
        publish {
            $0.phase = .waitingForClient
            $0.pendingClientName = nil
        }
    }

    /// Người dùng bấm đồng ý/từ chối cho `draft.install` hoặc `draft.rollback`.
    public func decideInstall(id: UUID, approved: Bool) async {
        if approved {
            await ExtensionDebugInstallGate.shared.approve(id: id)
        } else {
            await ExtensionDebugInstallGate.shared.reject(id: id)
        }
    }

    /// URI dán sang VS Code và cũng là nội dung QR. Chứa **host + port + token** (service chỉ để hiển
    /// thị); host là đường kết nối chính vì Bonjour không phải lúc nào cũng đăng ký được. Token không
    /// bao giờ vào TXT record hay log.
    private static func pairingURI(host: String?, serviceName: String, port: UInt16?, token: String) -> String {
        var components = URLComponents()
        components.scheme = "freebook-extdebug"
        components.host = "pair"
        components.queryItems = [
            URLQueryItem(name: "host", value: host ?? ""),
            URLQueryItem(name: "service", value: serviceName),
            URLQueryItem(name: "port", value: port.map(String.init) ?? ""),
            URLQueryItem(name: "token", value: token)
        ]
        return components.string ?? ""
    }
}
