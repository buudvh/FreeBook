import Foundation

/// Snapshot bất biến trạng thái debug server, để tầng Views vẽ mà không giữ tham chiếu tới actor.
///
/// Không còn field nào liên quan pairing: từ 1.3.305 server nghe là nối được, đúng như một server API
/// thường trên LAN. Thứ duy nhất người dùng cần là `websocketEndpoint`.
///
/// Yêu cầu cài/rollback đang chờ bấm **không** ở đây: nó thuộc `ExtensionDebugInstallGate`, và
/// `ExtensionDebugServerReader` gộp hai stream lại.
public struct ExtensionDebugServerStatus: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case stopped
        case starting
        /// Đang lắng nghe, chưa có client nào nối.
        case listening
        case connected
        case failed
    }

    public var phase: Phase
    public var port: UInt16?
    /// IPv4 của thiết bị trên Wi-Fi. `nil` khi chưa lấy được (chưa vào Wi-Fi).
    public var host: String?
    public var clientName: String?
    public var failureMessage: String?

    public init(
        phase: Phase = .stopped,
        port: UInt16? = nil,
        host: String? = nil,
        clientName: String? = nil,
        failureMessage: String? = nil
    ) {
        self.phase = phase
        self.port = port
        self.host = host
        self.clientName = clientName
        self.failureMessage = failureMessage
    }

    /// Endpoint mà debugger nối vào. Cổng cố định nên chuỗi này không đổi giữa các lượt bật.
    public var websocketEndpoint: String? {
        guard let port else { return nil }
        return "ws://\(host ?? "<ip-thiết-bị>"):\(port)"
    }

    public var isRunning: Bool {
        switch phase {
        case .stopped, .failed: return false
        case .starting, .listening, .connected: return true
        }
    }

    public var phaseLabel: String {
        switch phase {
        case .stopped: return "Đã tắt"
        case .starting: return "Đang mở…"
        case .listening: return "Đang lắng nghe"
        case .connected: return "Đã kết nối"
        case .failed: return "Lỗi"
        }
    }
}
