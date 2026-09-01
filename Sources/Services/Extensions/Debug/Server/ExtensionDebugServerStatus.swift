import Foundation

/// Snapshot bất biến trạng thái debug server, để tầng Views vẽ mà không giữ tham chiếu tới actor.
///
/// `pairingURI` là thứ người dùng dán sang VS Code và là nội dung của QR. Nó **chứa token**, nên chỉ
/// tồn tại trong snapshot khi server đang chờ pair và **không bao giờ** được log hay đưa vào
/// `ExtensionDebugEvent`.
public struct ExtensionDebugServerStatus: Sendable, Equatable {
    public enum Phase: String, Sendable {
        case stopped
        case starting
        /// Đang lắng nghe, đã quảng bá Bonjour, chờ client gửi token.
        case waitingForClient
        /// Client đã gửi token đúng, đang chờ người dùng bấm đồng ý trên thiết bị.
        case waitingForApproval
        case paired
        case failed
    }

    public var phase: Phase
    public var port: UInt16?
    /// IPv4 của thiết bị trên Wi-Fi. Đây là đường kết nối **chính**: client chỉ cần `ws://host:port`.
    public var host: String?
    /// Chỉ có giá trị khi Bonjour đăng ký được. `nil` là đang chạy thuần IP:port — vẫn hoạt động.
    public var serviceName: String?
    public var pairingURI: String?
    public var pairingExpiresAt: Date?
    public var pendingClientName: String?
    public var pairedClientName: String?
    public var failureMessage: String?
    /// Ghi chú không phải lỗi, ví dụ "Bonjour không đăng ký được, đã chuyển sang IP:port".
    public var bonjourNote: String?
    /// Yêu cầu cài/rollback đang chờ **bấm trên thiết bị** (Phase 4). `nil` là không có gì chờ.
    public var pendingInstallId: UUID?
    public var pendingInstallSummary: String?
    public var pendingInstallChanges: [String]

    public init(
        phase: Phase = .stopped,
        port: UInt16? = nil,
        host: String? = nil,
        serviceName: String? = nil,
        pairingURI: String? = nil,
        pairingExpiresAt: Date? = nil,
        pendingClientName: String? = nil,
        pairedClientName: String? = nil,
        failureMessage: String? = nil,
        bonjourNote: String? = nil,
        pendingInstallId: UUID? = nil,
        pendingInstallSummary: String? = nil,
        pendingInstallChanges: [String] = []
    ) {
        self.phase = phase
        self.port = port
        self.host = host
        self.serviceName = serviceName
        self.pairingURI = pairingURI
        self.pairingExpiresAt = pairingExpiresAt
        self.pendingClientName = pendingClientName
        self.pairedClientName = pairedClientName
        self.failureMessage = failureMessage
        self.bonjourNote = bonjourNote
        self.pendingInstallId = pendingInstallId
        self.pendingInstallSummary = pendingInstallSummary
        self.pendingInstallChanges = pendingInstallChanges
    }

    /// Endpoint mà debugger nối vào — dạng như một server API thường.
    public var websocketEndpoint: String? {
        guard let host, let port else { return nil }
        return "ws://\(host):\(port)"
    }

    public var isRunning: Bool {
        switch phase {
        case .stopped, .failed: return false
        case .starting, .waitingForClient, .waitingForApproval, .paired: return true
        }
    }

    public var phaseLabel: String {
        switch phase {
        case .stopped: return "Đã tắt"
        case .starting: return "Đang mở…"
        case .waitingForClient: return "Chờ máy phát triển kết nối"
        case .waitingForApproval: return "Chờ bạn xác nhận trên thiết bị"
        case .paired: return "Đã ghép nối"
        case .failed: return "Lỗi"
        }
    }
}
