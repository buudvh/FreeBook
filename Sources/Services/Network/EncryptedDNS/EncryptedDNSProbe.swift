import Foundation
import Network

/// Một lượt dò máy chủ DoH: mở kết nối TCP tới `captive.apple.com:80` với privacy context **riêng** bắt buộc tra tên qua
/// máy chủ đã chọn. Tới `.ready` ⇔ tra được tên qua DNS mã hoá và tới được đích. Context riêng nên lượt dò không đụng
/// `NWParameters.PrivacyContext.default` — dò được cả khi app đang bật lẫn đang lùi về DNS thường.
///
/// Chỉ chứng minh **máy chủ DoH tới được**, không chứng minh `URLSession` thật sự theo context mặc định (Apple không ghi
/// rõ). Máy đã cài DNS mã hoá cấp hệ thống thì hệ thống thắng, lượt dò đo luôn đường đó.
enum EncryptedDNSProbe {
    enum Outcome: Equatable, Sendable {
        case reachable
        case failed(String)
    }

    private static let probeHost = "captive.apple.com"
    private static let probePort: NWEndpoint.Port = 80
    private static let timeoutSeconds = 6

    static func run(resolver: EncryptedDNSResolver) async -> Outcome {
        let context = NWParameters.PrivacyContext(description: "TangCongCac.EncryptedDNSProbe")
        context.requireEncryptedNameResolution(true, fallbackResolver: resolver.resolverConfiguration)
        let parameters = NWParameters.tcp
        parameters.setPrivacyContext(context)
        let connection = NWConnection(host: NWEndpoint.Host(probeHost), port: probePort, using: parameters)
        let queue = DispatchQueue(label: "TangCongCac.EncryptedDNSProbe")

        return await withCheckedContinuation { continuation in
            let completion = Completion(connection: connection, continuation: continuation)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    completion.finish(.reachable)
                case .waiting(let error), .failed(let error):
                    // `.waiting` = không tra được tên / không tới được đích và NWConnection sẽ tự thử lại mãi —
                    // với lượt dò đó là lỗi (chỉ dò khi máy có mạng).
                    completion.finish(.failed(Self.describe(error)))
                default:
                    break
                }
            }
            queue.asyncAfter(deadline: .now() + .seconds(Self.timeoutSeconds)) {
                completion.finish(.failed("quá \(Self.timeoutSeconds) giây không phản hồi"))
            }
            connection.start(queue: queue)
        }
    }

    /// Resume đúng **một** lần (kết nối xong / lỗi / hết giờ — cái nào tới trước), rồi huỷ kết nối.
    private final class Completion: @unchecked Sendable {
        private let lock = NSLock()
        private let connection: NWConnection
        private var continuation: CheckedContinuation<Outcome, Never>?

        init(connection: NWConnection, continuation: CheckedContinuation<Outcome, Never>) {
            self.connection = connection
            self.continuation = continuation
        }

        func finish(_ outcome: Outcome) {
            lock.lock()
            let waiting = continuation
            continuation = nil
            lock.unlock()
            guard let waiting else { return }
            connection.stateUpdateHandler = nil
            connection.cancel()
            waiting.resume(returning: outcome)
        }
    }

    private static func describe(_ error: NWError) -> String {
        switch error {
        case .dns(let code):
            return "không tra được tên miền (DNS \(code))"
        case .posix(let code):
            return "lỗi mạng (\(code.rawValue))"
        case .tls(let status):
            return "lỗi TLS (\(status))"
        @unknown default:
            return String(describing: error)
        }
    }
}
