import Foundation
import Network

/// Chọn đường mạng cho request của **một nguồn** (tiện ích JS / nguồn Legado) theo cờ `Extension.encryptedDNSEnabled`
/// (1.3.831). Gọi được từ thread bất kỳ; khi không ai bật cờ thì thoát ngay, không tra bản ghi tiện ích.
///
/// Đi **thẳng** (`URLSession.shared` / không proxy) khi: không nguồn nào bật cờ, đang không có máy chủ DoH dùng được
/// (`EncryptedDNSRouting.activeResolver == nil` — tắt hẳn hoặc đang lùi), công tắc "Bật cho cả app" đang áp (context mặc
/// định đã lo), nguồn này không bật cờ, hoặc proxy nội bộ chưa sẵn. Còn lại ⇒ qua proxy nội bộ `EncryptedDNSRelay`.
///
/// Session qua proxy dùng `.default` (chung `HTTPCookieStorage.shared` + `URLCache.shared` với `URLSession.shared`,
/// nên cookie của `fetch` / `WebKitCookieBridge` vẫn dùng chung), dựng một lần mỗi cổng — listener bật lại thì cổng
/// đổi, dựng lại.
enum EncryptedDNSSessionRouter {
    private final class SessionCache: @unchecked Sendable {
        let lock = NSLock()
        var port: UInt16?
        var session: URLSession?
    }

    private static let cache = SessionCache()
    /// Chờ proxy sẵn sàng (chỉ khi gọi ngoài main thread — xem `EncryptedDNSRelay.waitForPort`).
    private static let relayWait: TimeInterval = 2

    /// Session cho `fetch` của tiện ích có `localPath` (`JSExecutor`).
    static func session(forExtensionPath path: String?) -> URLSession {
        guard let path, let port = relayPort(packageId: { ExtensionLibraryRepository.packageId(forLocalPath: path) }) else {
            return .shared
        }
        return session(forPort: port)
    }

    /// Proxy cho session tự dựng của nguồn (`LegadoHTTPClient`); rỗng ⇒ đi thẳng.
    static func proxyConfigurations(forPackageId packageId: String?) -> [ProxyConfiguration] {
        guard let packageId, let port = relayPort(packageId: { packageId }) else { return [] }
        return [proxyConfiguration(port: port)]
    }

    // MARK: - Nội bộ

    /// `packageId` truyền dạng closure để chỉ tra (tốn công với `localPath`) khi các điều kiện rẻ đã qua.
    private static func relayPort(packageId: () -> String?) -> UInt16? {
        let routing = EncryptedDNSRouting.current
        guard routing.hasEnabledSources, routing.activeResolver != nil, !routing.isGlobalApplied,
              let packageId = packageId(),
              ExtensionLibraryRepository.snapshot(packageId: packageId)?.encryptedDNSEnabled == true else {
            return nil
        }
        guard let port = EncryptedDNSRelay.shared.waitForPort(timeout: relayWait) else {
            AppLogger.shared.log("❌ [DNS-Relay] Proxy nội bộ chưa sẵn — \(packageId) đi DNS thường lượt này")
            return nil
        }
        return port
    }

    private static func proxyConfiguration(port: UInt16) -> ProxyConfiguration {
        let endpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port) ?? .any)
        return ProxyConfiguration(httpCONNECTProxy: endpoint, tlsOptions: nil)
    }

    private static func session(forPort port: UInt16) -> URLSession {
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let session = cache.session, cache.port == port { return session }
        cache.session?.finishTasksAndInvalidate()
        let configuration = URLSessionConfiguration.default
        configuration.proxyConfigurations = [proxyConfiguration(port: port)]
        let session = URLSession(configuration: configuration)
        cache.port = port
        cache.session = session
        return session
    }
}
