import Foundation

/// Quyền pairing của debug server: sinh token, hết hạn, dùng một lần, và cửa **xác nhận trên thiết bị**.
///
/// Ba luật của Phase 0 được cưỡng chế ở đây, không phải ở chỗ gọi:
/// 1. Token 256-bit sinh bằng `SystemRandomNumberGenerator`, **dùng một lần**: `consume` xoá nó.
/// 2. Hết hạn ngắn (`ttl`), mặc định 3 phút — QR để lâu trên bàn không còn dùng được.
/// 3. Token đúng **chỉ mở cửa xin phép**, không tự cấp session: người dùng phải bấm đồng ý trên máy.
///    Đây là thứ chặn một client trong cùng LAN đọc lỏm được token vẫn không vào được.
///
/// Token **không bao giờ** vào Bonjour TXT record, vào log, hay vào bất kỳ `ExtensionDebugEvent` nào.
public actor ExtensionDebugPairingAuthority {
    public static let defaultTTL: TimeInterval = 180

    public enum ApprovalState: String, Sendable {
        case idle
        case waitingForApproval
        case approved
        case rejected
    }

    private var token: String?
    private var expiresAt: Date?
    private var pairedClientName: String?
    private(set) public var approval: ApprovalState = .idle
    private var pendingClientName: String?

    public init() {}

    /// Sinh token mới cho một lượt bật server. Token cũ (nếu có) bị bỏ ngay.
    public func issueToken(ttl: TimeInterval = defaultTTL) -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        var generator = SystemRandomNumberGenerator()
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: .min ... .max, using: &generator)
        }
        let value = bytes.map { String(format: "%02x", $0) }.joined()
        token = value
        expiresAt = Date().addingTimeInterval(ttl)
        approval = .idle
        pendingClientName = nil
        pairedClientName = nil
        return value
    }

    public var isTokenValid: Bool {
        guard token != nil, let expiresAt else { return false }
        return expiresAt > Date()
    }

    public var currentExpiry: Date? { expiresAt }
    public var currentPendingClient: String? { pendingClientName }
    public var currentPairedClient: String? { pairedClientName }

    /// Client gửi token. Đúng và còn hạn ⇒ chuyển sang chờ người dùng bấm đồng ý; **chưa** paired.
    public func requestPairing(token candidate: String, clientName: String) -> Result<Void, ExtensionDebugProtocol.ErrorCode> {
        guard let token, let expiresAt else { return .failure(.pairingExpired) }
        guard expiresAt > Date() else { return .failure(.pairingExpired) }
        // So sánh hằng thời gian: token là bí mật, tránh rò độ dài khớp qua thời gian.
        guard Self.constantTimeEquals(token, candidate) else { return .failure(.pairingRejected) }
        pendingClientName = clientName
        approval = .waitingForApproval
        return .success(())
    }

    /// Người dùng bấm đồng ý trên thiết bị. Token bị **tiêu thụ** tại đây — dùng một lần.
    public func approvePending() {
        guard approval == .waitingForApproval else { return }
        pairedClientName = pendingClientName
        pendingClientName = nil
        token = nil
        expiresAt = nil
        approval = .approved
    }

    public func rejectPending() {
        pendingClientName = nil
        approval = .rejected
    }

    public var isPaired: Bool { approval == .approved }

    public func reset() {
        token = nil
        expiresAt = nil
        pendingClientName = nil
        pairedClientName = nil
        approval = .idle
    }

    private static func constantTimeEquals(_ lhs: String, _ rhs: String) -> Bool {
        let left = Array(lhs.utf8)
        let right = Array(rhs.utf8)
        guard left.count == right.count else { return false }
        var diff: UInt8 = 0
        for index in left.indices {
            diff |= left[index] ^ right[index]
        }
        return diff == 0
    }
}
