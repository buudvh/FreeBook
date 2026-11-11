import Foundation
import Network

/// Máy chủ DNS mã hoá (DoH) có sẵn cho Cài đặt › Chung › Mạng & DNS (1.3.825). Không cho tự nhập: mỗi máy chủ cần
/// **IP khởi động** (`bootstrapAddresses`) để tới được chính nó mà không phải tra DNS thường — tra tên máy chủ DoH bằng
/// DNS của nhà mạng là tự đẩy mình vào đúng chỗ đang bị chặn.
///
/// Raw value lưu ở `UserDefaults` (`EncryptedDNSPolicy.resolverKey`) — đừng đổi.
enum EncryptedDNSResolver: String, CaseIterable, Identifiable, Sendable {
    case cloudflare
    case google
    case adguardUnfiltered
    case quad9

    var id: String { rawValue }

    /// Tên trong picker của Cài đặt.
    var title: String {
        switch self {
        case .cloudflare: return "Cloudflare (1.1.1.1)"
        case .google: return "Google (8.8.8.8)"
        case .adguardUnfiltered: return "AdGuard không lọc"
        case .quad9: return "Quad9 (9.9.9.9)"
        }
    }

    /// Tên ngắn cho dòng trạng thái và log.
    var shortTitle: String {
        switch self {
        case .cloudflare: return "Cloudflare"
        case .google: return "Google"
        case .adguardUnfiltered: return "AdGuard"
        case .quad9: return "Quad9"
        }
    }

    /// Điểm DoH (RFC 8484). Chứng chỉ TLS khớp tên miền trong URL; IP khởi động chỉ để tới được máy.
    var endpointURL: URL {
        switch self {
        case .cloudflare: return URL(string: "https://cloudflare-dns.com/dns-query")!
        case .google: return URL(string: "https://dns.google/dns-query")!
        case .adguardUnfiltered: return URL(string: "https://unfiltered.adguard-dns.com/dns-query")!
        case .quad9: return URL(string: "https://dns.quad9.net/dns-query")!
        }
    }

    /// IP công bố của từng máy chủ (IPv4 trước, IPv6 sau).
    var bootstrapAddresses: [String] {
        switch self {
        case .cloudflare: return ["1.1.1.1", "1.0.0.1", "2606:4700:4700::1111", "2606:4700:4700::1001"]
        case .google: return ["8.8.8.8", "8.8.4.4", "2001:4860:4860::8888", "2001:4860:4860::8844"]
        case .adguardUnfiltered: return ["94.140.14.140", "94.140.14.141", "2a10:50c0::1:ff", "2a10:50c0::2:ff"]
        case .quad9: return ["9.9.9.9", "149.112.112.112", "2620:fe::fe", "2620:fe::9"]
        }
    }

    /// Cấu hình đưa vào `requireEncryptedNameResolution(_:fallbackResolver:)`. Máy đã cài DNS mã hoá cấp hệ thống
    /// (profile, app 1.1.1.1) thì hệ thống thắng, cấu hình này chỉ là dự phòng — đúng ý: cả máy đã tránh được chặn.
    var resolverConfiguration: NWParameters.PrivacyContext.ResolverConfiguration {
        let servers = bootstrapAddresses.map { NWEndpoint.hostPort(host: NWEndpoint.Host($0), port: 443) }
        return .https(endpointURL, serverAddresses: servers)
    }
}
