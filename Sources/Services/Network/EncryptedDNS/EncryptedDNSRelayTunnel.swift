import Foundation
import Network

/// Một kết nối vào proxy nội bộ `EncryptedDNSRelay` (1.3.831): đọc header, mở kết nối ra ngoài bằng `NWConnection` với
/// privacy context **bắt buộc DoH** (`EncryptedDNSRouting.activeResolver`; `nil` ⇒ DNS thường — tự lùi), rồi bơm dữ liệu
/// hai chiều.
///
/// - `CONNECT host:port` (https và mọi kết nối TCP khác): trả `200 Connection Established` rồi bơm.
/// - `GET http://…` (URL tuyệt đối — request `http://` qua proxy): viết lại dòng đầu thành đường dẫn, ép
///   `Connection: close` + bỏ `Proxy-Connection` (để `URLSession` không dùng lại kết nối này cho host khác), gửi tới
///   `host:80` rồi bơm.
/// - **Vòng đời** (mỗi request giờ tốn hai socket — repo từng cạn fd): kết nối ra ngoài có hạn 10 s (`.waiting` = lỗi
///   ⇒ 502); một bên đóng / lỗi ⇒ huỷ **cả hai**; 60 s không có byte nào ⇒ đóng.
/// - Log thường `[DNS-Relay] → host:port (…)` mỗi tunnel (chỉ host, không URL) để kiểm request có đi qua proxy; lỗi có `❌`.
final class EncryptedDNSRelayTunnel: @unchecked Sendable {
    private static let headerLimit = 16 * 1024
    private static let connectTimeout: TimeInterval = 10
    private static let idleTimeout: TimeInterval = 60
    private static let chunkSize = 64 * 1024
    private static let headerTerminator = Data("\r\n\r\n".utf8)

    private let client: NWConnection
    private let queue = DispatchQueue(label: "TangCongCac.EncryptedDNSRelay.tunnel")
    private let onClose: @Sendable (EncryptedDNSRelayTunnel) -> Void
    private var upstream: NWConnection?
    private var isUpstreamReady = false
    private var isRejecting = false
    private var header = Data()
    private var isClosed = false
    private var lastActivity = Date()
    private var target = ""

    init(client: NWConnection, onClose: @escaping @Sendable (EncryptedDNSRelayTunnel) -> Void) {
        self.client = client
        self.onClose = onClose
    }

    func start() {
        client.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close()
            default: break
            }
        }
        client.start(queue: queue)
        readHeader()
        scheduleIdleCheck()
    }

    /// Đóng cả hai phía. Idempotent, gọi được từ thread bất kỳ.
    func close() {
        queue.async { self.closeOnQueue() }
    }

    // MARK: - Header

    private func readHeader() {
        client.receive(minimumIncompleteLength: 1, maximumLength: 8 * 1024) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data { self.header.append(data) }
            if let end = self.header.range(of: Self.headerTerminator)?.upperBound {
                self.handleHeader(end: end)
            } else if error != nil || isComplete || self.header.count > Self.headerLimit {
                self.closeOnQueue()
            } else {
                self.readHeader()
            }
        }
    }

    private func handleHeader(end: Data.Index) {
        let rest = Data(header[end...])
        let text = String(decoding: header[..<end], as: UTF8.self)
        var lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        let parts = lines.isEmpty ? [] : lines.removeFirst().split(separator: " ").map(String.init)
        guard parts.count >= 3 else { return reject("400 Bad Request", why: "dòng đầu hỏng") }
        let method = parts[0].uppercased()
        if method == "CONNECT" {
            guard let endpoint = Self.hostPort(parts[1], defaultPort: 443) else {
                return reject("400 Bad Request", why: "CONNECT sai đích")
            }
            openUpstream(host: endpoint.host, port: endpoint.port) { [weak self] in
                guard let self else { return }
                self.sendToClient(Data("HTTP/1.1 200 Connection Established\r\n\r\n".utf8)) {
                    if !rest.isEmpty { self.upstream?.send(content: rest, completion: .contentProcessed { _ in }) }
                    self.startPumps()
                }
            }
        } else if let url = URLComponents(string: parts[1]), url.scheme?.lowercased() == "http",
                  let host = url.host, !host.isEmpty {
            // Giữ nguyên phần đã mã hoá % của đường dẫn / query (đường dẫn giải mã rồi ghép lại sẽ hỏng ký tự đặc biệt).
            var path = url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath
            if let query = url.percentEncodedQuery { path += "?" + query }
            let kept = lines.filter { line in
                let name = line.split(separator: ":", maxSplits: 1).first?.lowercased() ?? ""
                return name != "connection" && name != "proxy-connection" && name != "proxy-authorization"
            }
            let rebuilt = ([method + " " + path + " " + parts[2]] + kept + ["Connection: close", "", ""]).joined(separator: "\r\n")
            guard let upstreamPort = UInt16(exactly: url.port ?? 80) else {
                return reject("400 Bad Request", why: "cổng sai")
            }
            openUpstream(host: host, port: upstreamPort) { [weak self] in
                guard let self else { return }
                self.upstream?.send(content: Data(rebuilt.utf8) + rest, completion: .contentProcessed { _ in })
                self.startPumps()
            }
        } else {
            reject("405 Method Not Allowed", why: "kiểu request không hỗ trợ: \(method)")
        }
    }

    /// `host:port`, `[v6]:port` hoặc `host` (cổng mặc định).
    private static func hostPort(_ authority: String, defaultPort: UInt16) -> (host: String, port: UInt16)? {
        if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
            let host = String(authority[authority.index(after: authority.startIndex)..<close])
            let tail = authority[authority.index(after: close)...]
            let port = tail.hasPrefix(":") ? UInt16(tail.dropFirst()) : defaultPort
            return host.isEmpty ? nil : port.map { (host: host, port: $0) }
        }
        let pieces = authority.split(separator: ":", omittingEmptySubsequences: false)
        guard let first = pieces.first, !first.isEmpty, pieces.count <= 2 else { return nil }
        let port = pieces.count == 2 ? UInt16(pieces[1]) : defaultPort
        return port.map { (host: String(first), port: $0) }
    }

    // MARK: - Kết nối ra ngoài

    private func openUpstream(host: String, port: UInt16, onReady: @escaping @Sendable () -> Void) {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { return reject("400 Bad Request", why: "cổng sai") }
        target = "\(host):\(port)"
        let parameters = NWParameters.tcp
        let resolver = EncryptedDNSRouting.activeResolver
        if let resolver {
            parameters.setPrivacyContext(EncryptedDNSRelay.shared.privacyContext(for: resolver))
        }
        AppLogger.shared.log("[DNS-Relay] → \(target) (\(resolver.map { "DoH \($0.shortTitle)" } ?? "DNS thường"))")
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)
        upstream = connection
        isUpstreamReady = false
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, !self.isClosed else { return }
            switch state {
            case .ready:
                guard !self.isUpstreamReady else { return }
                self.isUpstreamReady = true
                onReady()
            case .waiting(let error), .failed(let error):
                if self.isUpstreamReady {
                    self.closeOnQueue()
                } else {
                    self.reject("502 Bad Gateway", why: "không mở được: \(error)")
                }
            case .cancelled:
                self.closeOnQueue()
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + Self.connectTimeout) { [weak self] in
            guard let self, !self.isClosed, !self.isUpstreamReady, self.upstream === connection else { return }
            self.reject("504 Gateway Timeout", why: "quá \(Int(Self.connectTimeout)) giây không kết nối được")
        }
    }

    // MARK: - Bơm dữ liệu

    private func startPumps() {
        guard let upstream else { return closeOnQueue() }
        pump(from: client, to: upstream)
        pump(from: upstream, to: client)
    }

    private func pump(from source: NWConnection, to sink: NWConnection) {
        source.receive(minimumIncompleteLength: 1, maximumLength: Self.chunkSize) { [weak self] data, _, isComplete, error in
            guard let self, !self.isClosed else { return }
            if let data, !data.isEmpty {
                self.lastActivity = Date()
                sink.send(content: data, completion: .contentProcessed { [weak self] sendError in
                    guard let self, !self.isClosed else { return }
                    if sendError != nil {
                        self.closeOnQueue()
                    } else if isComplete {
                        self.finish(sink)
                    } else {
                        self.pump(from: source, to: sink)
                    }
                })
            } else if isComplete || error != nil {
                self.finish(sink)
            } else {
                self.pump(from: source, to: sink)
            }
        }
    }

    /// Một phía hết dữ liệu: báo hết cho phía kia rồi đóng cả hai.
    private func finish(_ sink: NWConnection) {
        sink.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [weak self] _ in
            self?.closeOnQueue()
        })
    }

    // MARK: - Đóng

    private func reject(_ status: String, why: String) {
        // `.waiting` có thể báo nhiều lần trước khi 502 gửi xong ⇒ chỉ trả lỗi một lần, bỏ kết nối ra ngoài ngay.
        guard !isRejecting else { return }
        isRejecting = true
        upstream?.stateUpdateHandler = nil
        upstream?.cancel()
        AppLogger.shared.log("❌ [DNS-Relay] \(target.isEmpty ? "(chưa có đích)" : target): \(why)")
        sendToClient(Data("HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8)) { [weak self] in
            self?.closeOnQueue()
        }
    }

    private func sendToClient(_ data: Data, then next: @escaping @Sendable () -> Void) {
        client.send(content: data, completion: .contentProcessed { [weak self] error in
            guard let self, !self.isClosed else { return }
            if error != nil { self.closeOnQueue() } else { next() }
        })
    }

    private func scheduleIdleCheck() {
        queue.asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            guard let self, !self.isClosed else { return }
            if Date().timeIntervalSince(self.lastActivity) >= Self.idleTimeout {
                self.closeOnQueue()
            } else {
                self.scheduleIdleCheck()
            }
        }
    }

    /// Chạy trên `queue`.
    private func closeOnQueue() {
        guard !isClosed else { return }
        isClosed = true
        client.stateUpdateHandler = nil
        upstream?.stateUpdateHandler = nil
        client.cancel()
        upstream?.cancel()
        upstream = nil
        onClose(self)
    }
}
