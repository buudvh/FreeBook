import Foundation

/// Trạng thái DNS mã hoá mà màn Mạng & DNS hiện (`EncryptedDNSRepository.state`).
///
/// `reachable` chỉ có nghĩa **máy chủ DoH tới được** (lượt dò của `EncryptedDNSProbe` qua được) — Apple không ghi rõ
/// `URLSession` có theo `NWParameters.PrivacyContext.default` hay không, nên chữ hiện ra không hứa "đang dùng".
enum EncryptedDNSState: Equatable, Sendable {
    /// Công tắc tắt — dùng DNS của nhà mạng.
    case off
    /// Đang dò máy chủ.
    case checking(EncryptedDNSResolver)
    /// Dò xong, máy chủ tới được; context mặc định đang bắt buộc DNS mã hoá.
    case reachable(EncryptedDNSResolver)
    /// Dò lỗi ⇒ đã lùi về DNS thường tới lượt dò sau (đổi mạng, mở lại app, bấm "Kiểm tra lại").
    case fallback(EncryptedDNSResolver, reason: String)
    /// Máy không có mạng — chưa dò, dò lại khi có mạng.
    case waitingForNetwork(EncryptedDNSResolver)

    var isChecking: Bool {
        if case .checking = self { return true }
        return false
    }

    /// Một dòng cho Cài đặt.
    var statusText: String {
        switch self {
        case .off:
            return "Đang dùng DNS của nhà mạng"
        case .checking(let resolver):
            return "Đang kiểm tra máy chủ \(resolver.shortTitle)…"
        case .reachable(let resolver):
            return "Máy chủ DoH tới được (\(resolver.shortTitle))"
        case .fallback(_, let reason):
            return "Đang lùi về DNS thường: \(reason)"
        case .waitingForNetwork:
            return "Chưa có mạng — sẽ kiểm tra khi có mạng"
        }
    }
}
