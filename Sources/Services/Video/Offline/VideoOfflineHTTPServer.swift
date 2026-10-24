import Foundation
import Network

/// Server HTTP tối giản **chỉ nghe 127.0.0.1** để AVPlayer phát HLS đã tải: AVPlayer không chính thức phát m3u8 từ
/// `file://`, còn resource loader không phục vụ được đoạn media. File mp4 đơn không cần server (phát `file://`).
///
/// - Cổng ngẫu nhiên, đường dẫn bắt đầu bằng token ngẫu nhiên của mỗi lần bật — app khác trên máy (cũng thấy được
///   127.0.0.1) không đoán được URL. Chỉ phục vụ file dưới `videos/` (`VideoOfflineStore.resolveRelativePath`).
/// - Bật theo nhu cầu (`url(forRelativePath:)` chờ `.ready`), tắt khi trình phát `stop()`. App bị treo nền có thể làm
///   listener chết ⇒ lần gọi sau tự bật lại (cổng/token mới); playlist local chỉ dùng URI tương đối nên chỉ URL item đổi.
/// - Phần đọc request / trả file nằm ở `VideoOfflineHTTPResponder`.
final class VideoOfflineHTTPServer: @unchecked Sendable {
    static let shared = VideoOfflineHTTPServer()
    private static let readyTimeout: TimeInterval = 3

    private let queue = DispatchQueue(label: "FreeBook.VideoOfflineHTTPServer")
    private var listener: NWListener?
    private var port: UInt16?
    private var token = ""
    private var waiters: [CheckedContinuation<(port: UInt16, token: String)?, Never>] = []
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    private init() {}

    /// URL phát của một file dưới `videos/`; `nil` khi không bật được server (đã log ❌).
    func url(forRelativePath relativePath: String) async -> URL? {
        guard let endpoint = await ensureRunning() else { return nil }
        let encoded = relativePath
            .split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        return URL(string: "http://127.0.0.1:\(endpoint.port)/\(endpoint.token)/\(encoded)")
    }

    func stop() {
        queue.async {
            guard self.listener != nil else { return }
            self.teardown(reason: "trình phát đóng")
        }
    }

    // MARK: - Vòng đời listener

    private func ensureRunning() async -> (port: UInt16, token: String)? {
        await withCheckedContinuation { continuation in
            queue.async {
                if let port = self.port, self.listener != nil {
                    continuation.resume(returning: (port, self.token))
                    return
                }
                self.waiters.append(continuation)
                if self.listener == nil {
                    self.startListener()
                }
            }
        }
    }

    /// Chạy trên `queue`.
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
            AppLogger.shared.log("❌ [VideoOfflineServer] Không tạo được listener 127.0.0.1: \(error.localizedDescription)")
            resumeWaiters(with: nil)
            return
        }
        token = UUID().uuidString.lowercased()
        listener = newListener
        newListener.stateUpdateHandler = { [weak self, weak newListener] state in
            guard let self, let newListener else { return }
            self.handle(state: state, of: newListener)
        }
        newListener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        newListener.start(queue: queue)
        // Listener kẹt ở `.setup`/`.waiting` thì người chờ không bao giờ được trả ⇒ quá hạn thì tắt, trả `nil` để trình
        // phát chuyển sang trực tuyến thay vì quay mãi.
        queue.asyncAfter(deadline: .now() + Self.readyTimeout) { [weak self, weak newListener] in
            guard let self, let newListener, self.listener === newListener, self.port == nil else { return }
            AppLogger.shared.log("❌ [VideoOfflineServer] Listener không sẵn sàng sau \(Int(Self.readyTimeout)) giây")
            self.teardown(reason: "quá hạn")
        }
    }

    /// Chạy trên `queue`.
    private func handle(state: NWListener.State, of source: NWListener) {
        guard source === listener else { return }
        switch state {
        case .ready:
            guard let rawPort = source.port?.rawValue else {
                AppLogger.shared.log("❌ [VideoOfflineServer] Listener sẵn sàng nhưng không có cổng")
                teardown(reason: "không có cổng")
                return
            }
            port = rawPort
            AppLogger.shared.log("📡 [VideoOfflineServer] Đang nghe 127.0.0.1:\(rawPort)")
            resumeWaiters(with: (rawPort, token))
        case .failed(let error):
            AppLogger.shared.log("❌ [VideoOfflineServer] Listener lỗi: \(error.localizedDescription)")
            teardown(reason: "lỗi")
        case .cancelled:
            if listener === source { teardown(reason: "bị huỷ") }
        default:
            break
        }
    }

    /// Chạy trên `queue`. Idempotent.
    private func teardown(reason: String) {
        let current = listener
        listener = nil
        port = nil
        current?.stateUpdateHandler = nil
        current?.newConnectionHandler = nil
        current?.cancel()
        for connection in connections.values {
            connection.cancel()
        }
        connections.removeAll()
        resumeWaiters(with: nil)
        if current != nil {
            AppLogger.shared.log("📡 [VideoOfflineServer] Tắt server (\(reason))")
        }
    }

    private func resumeWaiters(with endpoint: (port: UInt16, token: String)?) {
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume(returning: endpoint)
        }
    }

    // MARK: - Kết nối

    /// Chạy trên `queue`.
    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.connections.removeValue(forKey: id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        let responder = VideoOfflineHTTPResponder(connection: connection, token: token)
        responder.start()
    }
}
