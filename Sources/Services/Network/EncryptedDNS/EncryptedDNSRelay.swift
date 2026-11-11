import Foundation
import Network

/// Proxy HTTP CONNECT nội bộ **chỉ nghe 127.0.0.1** để bật DNS mã hoá cho **riêng** từng tiện ích / nguồn Legado
/// (1.3.831). Apple không có API gắn DNS mã hoá cho một `URLSession` (chỉ có privacy context mặc định cho cả tiến
/// trình), nên request của nguồn bật cờ đi qua một `URLSession` có `proxyConfigurations` trỏ vào đây
/// (`EncryptedDNSSessionRouter`); mỗi kết nối vào là một `EncryptedDNSRelayTunnel`, tự tra tên miền qua DoH.
///
/// - Cổng ngẫu nhiên, khởi động lười (`start()` — `EncryptedDNSRepository` gọi sớm khi có nguồn bật cờ, để request
///   đầu tiên sau khi mở app không âm thầm đi đường thường). Khuôn listener như `VideoOfflineHTTPServer`.
/// - App bị treo nền có thể làm listener chết ⇒ lần hỏi cổng sau tự bật lại (cổng mới); router dựng lại session theo
///   cổng.
/// - Không xác thực: chỉ nhận kết nối loopback, và proxy chỉ mở kết nối ra ngoài — app khác trên máy tự làm được việc
///   đó, không lộ dữ liệu gì của app này.
final class EncryptedDNSRelay: @unchecked Sendable {
    static let shared = EncryptedDNSRelay()
    private static let readyTimeout: TimeInterval = 3

    private let queue = DispatchQueue(label: "TangCongCac.EncryptedDNSRelay")
    private var listener: NWListener?
    private var port: UInt16?
    private var tunnels: [ObjectIdentifier: EncryptedDNSRelayTunnel] = [:]
    /// Privacy context bắt buộc DoH, mỗi máy chủ một bản dùng lại (giữ được bộ đệm tên miền giữa các kết nối).
    private var contexts: [EncryptedDNSResolver: NWParameters.PrivacyContext] = [:]
    private let contextLock = NSLock()

    private init() {}

    // MARK: - API

    /// Bật listener nếu chưa chạy (không chờ).
    func start() {
        queue.async {
            if self.listener == nil { self.startListener() }
        }
    }

    /// Tắt listener + mọi tunnel (không còn nguồn nào bật cờ).
    func stop() {
        queue.async {
            self.teardown(reason: "không còn nguồn bật DNS riêng")
        }
    }

    /// Cổng đang nghe; chưa sẵn thì bật và chờ tối đa `timeout` — **chỉ chờ khi không ở main thread** (đang ở main thì
    /// trả ngay giá trị hiện có, có thể `nil`). `nil` ⇒ caller đi đường thường.
    func waitForPort(timeout: TimeInterval) -> UInt16? {
        if let ready = currentPort() { return ready }
        start()
        guard !Thread.isMainThread else { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            usleep(50_000)
            if let ready = currentPort() { return ready }
        }
        return currentPort()
    }

    /// Privacy context bắt buộc DoH qua `resolver` (dùng cho kết nối ra ngoài của tunnel).
    func privacyContext(for resolver: EncryptedDNSResolver) -> NWParameters.PrivacyContext {
        contextLock.lock()
        defer { contextLock.unlock() }
        if let existing = contexts[resolver] { return existing }
        let context = NWParameters.PrivacyContext(description: "TangCongCac.EncryptedDNSRelay.\(resolver.rawValue)")
        context.requireEncryptedNameResolution(true, fallbackResolver: resolver.resolverConfiguration)
        contexts[resolver] = context
        return context
    }

    private func currentPort() -> UInt16? {
        queue.sync { listener != nil ? port : nil }
    }

    // MARK: - Listener (chạy trên `queue`)

    private func startListener() {
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .loopback
        parameters.acceptLocalOnly = true
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters)
        } catch {
            AppLogger.shared.log("❌ [DNS-Relay] Không tạo được listener 127.0.0.1: \(error.localizedDescription)")
            return
        }
        listener = newListener
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self, let newListener else { return }
            self.handle(state: state, of: newListener)
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        newListener.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.readyTimeout) { [weak self, weak newListener] in
            guard let self, let newListener, self.listener === newListener, self.port == nil else { return }
            AppLogger.shared.log("❌ [DNS-Relay] Listener không sẵn sàng sau \(Int(Self.readyTimeout)) giây")
            self.teardown(reason: "quá hạn")
        }
    }

    private func handle(state: NWListener.State, of source: NWListener) {
        guard source === listener else { return }
        switch state {
        case .ready:
            guard let rawPort = source.port?.rawValue else {
                AppLogger.shared.log("❌ [DNS-Relay] Listener sẵn sàng nhưng không có cổng")
                teardown(reason: "không có cổng")
                return
            }
            port = rawPort
            AppLogger.shared.log("[DNS-Relay] Đang nghe 127.0.0.1:\(rawPort)")
        case .failed(let error):
            AppLogger.shared.log("❌ [DNS-Relay] Listener lỗi: \(error.localizedDescription)")
            teardown(reason: "lỗi")
        case .cancelled:
            if listener === source { teardown(reason: "bị huỷ") }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        let tunnel = EncryptedDNSRelayTunnel(client: connection) { [weak self] closed in
            guard let self else { return }
            let key = ObjectIdentifier(closed)
            self.queue.async { self.tunnels[key] = nil }
        }
        tunnels[ObjectIdentifier(tunnel)] = tunnel
        tunnel.start()
    }

    /// Idempotent.
    private func teardown(reason: String) {
        let current = listener
        listener = nil
        port = nil
        current?.stateUpdateHandler = nil
        current?.newConnectionHandler = nil
        current?.cancel()
        let open = Array(tunnels.values)
        tunnels.removeAll()
        open.forEach { $0.close() }
        if current != nil {
            AppLogger.shared.log("[DNS-Relay] Tắt proxy nội bộ (\(reason))")
        }
    }
}
