import Foundation

/// Địa chỉ IPv4 của thiết bị trên Wi-Fi, để dựng chuỗi `ws://<ip>:<port>` hiện cho người dùng.
///
/// Đây là thứ thay cho Bonjour: client chỉ cần một thư viện WebSocket và địa chỉ này, không cần
/// dependency mDNS — thứ vốn không đáng tin trên Windows/Linux và bị hệ thống từ chối khi app chạy qua
/// LiveContainer (`NWError -65555 NoAuth`).
public enum ExtensionDebugNetworkAddress {
    /// Ưu tiên `en0` (Wi-Fi); nếu không có thì lấy interface IPv4 non-loopback đầu tiên.
    public static func currentIPv4() -> String? {
        var preferred: String?
        var fallback: String?

        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return nil }
        defer { freeifaddrs(head) }

        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = cursor {
            let interface = pointer.pointee
            cursor = interface.ifa_next

            guard let addr = interface.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addr,
                socklen_t(addr.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }

            let value = String(cString: host)
            guard !value.isEmpty else { continue }
            let name = String(cString: interface.ifa_name)
            if name == "en0" {
                preferred = value
            } else if fallback == nil {
                fallback = value
            }
        }

        return preferred ?? fallback
    }
}
