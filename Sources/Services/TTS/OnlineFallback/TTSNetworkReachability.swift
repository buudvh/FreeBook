import Foundation
import Network

/// Mạng của máy có dùng được không (`NWPathMonitor`) — cho giọng dự phòng (1.3.945): **mất mạng thì đọc dự phòng ngay**
/// (khỏi chờ TTS online hết giờ chờ + hết lượt thử lại) và **có mạng lại thì thử online ngay**.
///
/// Bắt đầu theo dõi ở lần hỏi đầu (`isSatisfied`); trước khi có kết quả đầu tiên coi như có mạng. Đổi trạng thái ⇒ báo
/// `TTSManager.onlineFallbackNetworkChanged` trên main.
final class TTSNetworkReachability: @unchecked Sendable {
    static let shared = TTSNetworkReachability()

    private let lock = NSLock()
    private var monitor: NWPathMonitor?
    private var satisfied = true
    private let queue = DispatchQueue(label: "freebook.tts.network-reachability", qos: .utility)

    private init() {}

    var isSatisfied: Bool {
        startIfNeeded()
        return lock.withLock { satisfied }
    }

    func startIfNeeded() {
        lock.lock()
        defer { lock.unlock() }
        guard monitor == nil else { return }
        let pathMonitor = NWPathMonitor()
        pathMonitor.pathUpdateHandler = { [weak self] path in
            self?.update(isSatisfied: path.status == .satisfied)
        }
        monitor = pathMonitor
        pathMonitor.start(queue: queue)
    }

    private func update(isSatisfied value: Bool) {
        let changed: Bool = lock.withLock {
            guard satisfied != value else { return false }
            satisfied = value
            return true
        }
        guard changed else { return }
        AppLogger.shared.log("[TTSFallback] Mạng \(value ? "có lại" : "mất")")
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                TTSManager.shared.onlineFallbackNetworkChanged(isSatisfied: value)
            }
        }
    }
}
