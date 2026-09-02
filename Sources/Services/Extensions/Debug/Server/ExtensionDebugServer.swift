import Foundation
import Network
import SwiftData

/// Debug server trên LAN. Bật là lắng nghe, không có bước ghép nối nào.
///
/// Mượn đúng hai quyết định của `LocalTTS/Services/LocalHTTPServer.swift`:
/// 1. **Cổng cố định** thay vì `.any` — địa chỉ không đổi giữa các lượt bật, người dùng không phải đọc
///    lại số cổng mỗi lần. Cổng đang dùng được **ghi nhớ** (`extDebugServerPort`), nên lần sau mở lại
///    đúng URL đó nếu cổng còn rảnh.
/// 2. `allowLocalEndpointReuse = true` — tắt rồi bật lại ngay không bị "address in use".
///
/// Khác LocalTTS ở một chỗ có chủ ý: **không** ràng buộc `requiredLocalEndpoint` về `127.0.0.1`.
/// LocalTTS phục vụ app khác trên cùng máy; ở đây client là máy tính khác trong cùng Wi-Fi nên phải
/// nghe trên mọi interface.
///
/// Vòng đời **không** gắn với màn hình hay `scenePhase`: rời màn Cài Đặt hay minimize app đều không làm
/// app tắt server. Nhưng cũng **không có keep-alive**: khi iOS treo tiến trình ở nền thì socket ngừng
/// nhận, và nhận lại khi app trở lại foreground.
public actor ExtensionDebugServer {
    public static let shared = ExtensionDebugServer()

    /// Cổng mặc định lần đầu; tránh trùng 17771 mà LocalTTS đang dùng.
    public static let defaultPort: UInt16 = 17772
    private static let portStorageKey = "extDebugServerPort"
    private static let maxRestartAttempts = 3

    private let queue = DispatchQueue(label: "com.freebook.extdebug.server")

    private var listener: NWListener?
    private var connection: ExtensionDebugConnection?
    private var router: ExtensionDebugCommandRouter?
    private var status = ExtensionDebugServerStatus()
    private var observers: [UUID: AsyncStream<ExtensionDebugServerStatus>.Continuation] = [:]
    private var container: ModelContainer?
    private var restartAttempts = 0
    /// Cổng đang thử. `nil` nghĩa là đã bỏ cổng ghi nhớ và để hệ thống cấp cổng bất kỳ.
    private var attemptedPort: UInt16?
    private var didFallbackToAnyPort = false

    public init() {}

    public var currentStatus: ExtensionDebugServerStatus { status }

    /// Cổng ghi nhớ của lượt bật trước. Lần sau mở lại đúng cổng này nếu nó còn rảnh.
    public static var rememberedPort: UInt16 {
        let saved = UserDefaults.standard.integer(forKey: portStorageKey)
        guard saved > 0, saved <= Int(UInt16.max) else { return defaultPort }
        return UInt16(saved)
    }

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

    public func start(container: ModelContainer) async {
        guard listener == nil else { return }
        self.container = container
        restartAttempts = 0
        didFallbackToAnyPort = false
        publish { $0 = ExtensionDebugServerStatus(phase: .starting) }
        launchListener(on: Self.rememberedPort)
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        connection?.close(reason: "Server đã tắt")
        connection = nil
        await router?.detach()
        router = nil
        restartAttempts = 0
        didFallbackToAnyPort = false
        attemptedPort = nil
        await ExtensionDebugRunner.shared.cancelAll()
        await ExtensionDebugInstallGate.shared.cancelPending()
        await ExtensionDraftStagingStore.shared.discardAll()
        publish { $0 = ExtensionDebugServerStatus(phase: .stopped) }
    }

    /// `port == nil` ⇒ để hệ thống cấp cổng bất kỳ (đường dự phòng khi cổng ghi nhớ đang bận).
    private func launchListener(on port: UInt16?) {
        guard let container else {
            publish { $0 = ExtensionDebugServerStatus(phase: .failed, failureMessage: "Chưa có ModelContainer") }
            return
        }
        router = ExtensionDebugCommandRouter(container: container)
        attemptedPort = port

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        do {
            let newListener: NWListener
            if let port, let endpointPort = NWEndpoint.Port(rawValue: port) {
                newListener = try NWListener(using: parameters, on: endpointPort)
            } else {
                newListener = try NWListener(using: parameters)
            }
            newListener.stateUpdateHandler = { [weak self] state in
                Task { await self?.handleListenerState(state) }
            }
            newListener.newConnectionHandler = { [weak self] connection in
                Task { await self?.accept(connection) }
            }
            listener = newListener
            newListener.start(queue: queue)
        } catch {
            handleLaunchFailure(message: error.localizedDescription)
        }
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            restartAttempts = 0
            let port = listener?.port?.rawValue ?? attemptedPort ?? Self.defaultPort
            // Ghi nhớ cổng thật sự mở được: lần bật sau dùng lại đúng URL này.
            UserDefaults.standard.set(Int(port), forKey: Self.portStorageKey)
            let host = ExtensionDebugNetworkAddress.currentIPv4()
            publish {
                $0.phase = .listening
                $0.port = port
                $0.host = host
                $0.failureMessage = nil
            }
        case .failed(let error):
            AppLogger.shared.log("⚠️ [ExtDebug] Listener lỗi: \(error.localizedDescription)")
            handleLaunchFailure(message: error.localizedDescription)
        case .cancelled:
            if restartAttempts == 0, !didFallbackToAnyPort {
                publish { $0 = ExtensionDebugServerStatus(phase: .stopped) }
            }
        default:
            break
        }
    }

    /// Ba bậc xử lý, theo đúng thứ tự: cổng ghi nhớ đang bận thì chuyển sang cổng bất kỳ; sau đó mới
    /// thử lại; hết lượt thử mới báo lỗi.
    private func handleLaunchFailure(message: String) {
        listener?.cancel()
        listener = nil
        router = nil

        if attemptedPort != nil, !didFallbackToAnyPort {
            didFallbackToAnyPort = true
            publish {
                $0.phase = .starting
                $0.failureMessage = "Cổng \(self.attemptedPort.map(String.init) ?? "?") đang bận — đang mở cổng khác."
            }
            launchListener(on: nil)
            return
        }

        guard restartAttempts < Self.maxRestartAttempts else {
            publish {
                $0.phase = .failed
                $0.failureMessage = message
            }
            return
        }
        restartAttempts += 1
        let attempt = restartAttempts
        publish {
            $0.phase = .starting
            $0.failureMessage = "Đang thử lại (\(attempt)/\(Self.maxRestartAttempts)): \(message)"
        }
        let retryPort = attemptedPort
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await self?.launchListener(on: retryPort)
        }
    }

    // MARK: - Kết nối

    private func accept(_ nwConnection: NWConnection) {
        guard connection == nil, let router else {
            // Chỉ nhận **một** client. Nếu client trước còn treo ở đây thì client mới bị từ chối
            // ngay, và phía client chỉ thấy "kết nối bị đóng" — log này là chỗ duy nhất phân biệt
            // được ca đó với ca server chưa chạy.
            AppLogger.shared.log("🚫 [ExtDebug] Từ chối kết nối \(String(describing: nwConnection.endpoint)): \(connection == nil ? "chưa có router" : "đã có client khác")")
            nwConnection.cancel()
            return
        }
        AppLogger.shared.log("🤝 [ExtDebug] Nhận kết nối từ \(String(describing: nwConnection.endpoint))")
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
        publish {
            $0.phase = .connected
            $0.failureMessage = nil
        }
    }

    private func send(_ envelope: ExtensionDebugProtocol.Envelope) {
        connection?.send(envelope)
    }

    private func route(_ data: Data) async {
        let name = await router?.handle(data)
        guard let name, !name.isEmpty else { return }
        publish { $0.clientName = name }
    }

    private func handleDisconnect(reason: String?) async {
        connection = nil
        await router?.detach()
        await ExtensionDebugRunner.shared.cancelAll()
        await ExtensionDebugInstallGate.shared.cancelPending()
        guard listener != nil else { return }
        publish {
            $0.phase = .listening
            $0.clientName = nil
            $0.failureMessage = reason
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
}
