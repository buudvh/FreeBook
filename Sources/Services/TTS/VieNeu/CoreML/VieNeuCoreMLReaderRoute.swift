import Foundation
import UIKit

/// Backend Core ML của **trình đọc** ("Tăng tốc Core ML", P2c cách B — báo cáo §16; luôn bật từ 1.3.919) — chỗ giữ duy nhất,
/// gọi được từ mọi luồng (khoá riêng).
///
/// - `backendForReader()`: mọi lượt tổng hợp Nano (`VieNeuTTSService.synthesizeWithDuration` — trình đọc, Nghe thử, nghe
///   thử giọng) lấy backend ở đây; `nil` ⇒ ORT.
/// - Có backend khi: gói đã qua tự kiểm (`VieNeuCoreMLAccelerator.isVerified`) và đã gắn (`VieNeuCoreMLAccelerator.prepare`
///   xong, hoặc `warmUpIfReady` lúc engine Nano khởi động). Session nạp lười theo bucket (~0,2 s mỗi session).
/// - Lỗi Core ML ở một chunk ⇒ engine chạy lại chunk đó bằng ORT (`fallsBackToORTOnError`); lỗi tới `maxFailures` lần ⇒
///   thôi dùng Core ML tới lần mở app sau.
final class VieNeuCoreMLReaderRoute: @unchecked Sendable {
    static let shared = VieNeuCoreMLReaderRoute()
    static let maxFailures = 3
    /// Nạp sẵn + chạy nháp khi engine Nano khởi động — các khung phủ hầu hết đoạn khi đọc truyện (VE T64/T96/T128,
    /// codec T64/T128, theo các lượt đo 1.3.915); khung khác (T160) nạp khi gặp.
    static let warmUpOrder: [(kind: String, bucket: Int)] = [
        ("ve", 64), ("codec", 64), ("ve", 96), ("codec", 128), ("ve", 128)
    ]

    private let lock = NSLock()
    private var backend: VieNeuCoreMLFlowBackend?
    private var disabledReason: String?
    private var isWarmingUp = false
    /// Đoạn Core ML / lùi ORT của các backend đã nhả — cộng với backend hiện tại cho `counters()`.
    private var releasedCoreML = 0
    private var releasedFallback = 0
    private var memoryObserver: NSObjectProtocol?

    private init() {
        // Thiếu RAM: nhả session (giữ backend, lượt sau nạp lại lười ~0,2 s mỗi session).
        memoryObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.trimSessions(reason: "máy báo thiếu RAM")
        }
    }

    /// Backend cho một lượt tổng hợp của trình đọc; `nil` ⇒ chạy ORT như cũ.
    func backendForReader() -> VieNeuFlowBackend? {
        lock.lock()
        defer { lock.unlock() }
        guard disabledReason == nil, let backend else { return nil }
        let failures = backend.statsSnapshot.failures
        if failures >= Self.maxFailures {
            disabledReason = "Core ML lỗi \(failures) lần"
            AppLogger.shared.log("❌ [VieNeuCoreML] Lỗi \(failures) lần — trình đọc dùng ORT tới lần mở app sau")
            return nil
        }
        return backend
    }

    /// Gắn backend đã nạp (sau bước chuẩn bị + tự kiểm của `VieNeuCoreMLAccelerator`).
    func install(_ newBackend: VieNeuCoreMLFlowBackend) {
        lock.lock()
        accumulateLocked()
        backend = newBackend
        disabledReason = nil
        lock.unlock()
        AppLogger.shared.log("🎙️ [VieNeuCoreML] Trình đọc dùng Core ML (\(newBackend.loadedSessionCount) session đã nạp)")
    }

    /// Nhả hẳn (đổi sang Turbo, nhả engine Nano, xoá gói Core ML). Lượt đang chạy giữ bản tham chiếu riêng tới backend nên
    /// chạy nốt bình thường.
    func release(reason: String) {
        lock.lock()
        let had = backend != nil
        accumulateLocked()
        let old = backend
        backend = nil
        lock.unlock()
        old?.releaseSessions()
        if had { AppLogger.shared.log("🎙️ [VieNeuCoreML] Nhả Core ML của trình đọc: \(reason)") }
    }

    /// Thiếu RAM: nhả session nhưng giữ backend — lượt sau nạp lại lười (~0,2 s mỗi session).
    func trimSessions(reason: String) {
        lock.lock()
        let current = backend
        lock.unlock()
        guard let current, current.loadedSessionCount > 0 else { return }
        current.releaseSessions()
        AppLogger.shared.log("🎙️ [VieNeuCoreML] Nhả session Core ML: \(reason)")
    }

    /// Nạp sẵn + chạy nháp lúc engine Nano khởi động (`VieNeuTTSService.warmUpCoreMLForReader`); mỗi khung một lần giữ khoá
    /// tổng hợp (`serialize`) để không chồng lên lượt đọc. Gói chưa qua tự kiểm ⇒ nhờ `VieNeuCoreMLAccelerator` tự tải +
    /// biên dịch + tự kiểm (Core ML luôn bật, 1.3.919); xong việc đó gọi lại hàm này.
    func warmUpIfReady(serialize: (() throws -> Void) throws -> Void) {
        guard VieNeuModelChoice.current == .nano else { return }
        guard let package = try? VieNeuCoreMLPackage(), let manifest = package.manifest,
              VieNeuCoreMLAccelerator.isVerified(package: package) else {
            AppLogger.shared.log("🎙️ [VieNeuCoreML] Chưa sẵn sàng (chưa tải / chưa tự kiểm) — trình đọc dùng ORT, tự chuẩn bị ở nền")
            Task { @MainActor in VieNeuCoreMLAccelerator.shared.prepareIfNeeded(reason: "engine Nano khởi động") }
            return
        }
        lock.lock()
        if isWarmingUp || disabledReason != nil {
            lock.unlock()
            return
        }
        isWarmingUp = true
        let target = backend ?? VieNeuCoreMLFlowBackend(
            package: package, manifest: manifest, sessionCap: manifest.veBuckets.count + manifest.codecBuckets.count,
            isReader: true
        )
        backend = target
        lock.unlock()
        defer {
            lock.lock()
            isWarmingUp = false
            lock.unlock()
        }

        let started = ProcessInfo.processInfo.systemUptime
        var warmed = 0
        for item in Self.warmUpOrder {
            let available = item.kind == "ve" ? manifest.veBuckets : manifest.codecBuckets
            guard available.contains(item.bucket) else { continue }
            do {
                try serialize {
                    try target.loadSession(kind: item.kind, bucket: item.bucket)
                    try target.warmUp(kind: item.kind, bucket: item.bucket)
                }
                warmed += 1
            } catch {
                AppLogger.shared.log("❌ [VieNeuCoreML] Chạy nháp \(item.kind) T\(item.bucket) lỗi: \(error.localizedDescription)")
            }
        }
        AppLogger.shared.log(String(
            format: "🎙️ [VieNeuCoreML] Nạp sẵn + chạy nháp %ld khung trong %.0f ms",
            warmed, (ProcessInfo.processInfo.systemUptime - started) * 1_000
        ))
    }

    /// Tổng đoạn chạy Core ML / lùi ORT (cộng dồn) — `[NghiEnergy] Summary` lấy hiệu giữa hai lần.
    func counters() -> (coreML: Int, fallback: Int) {
        lock.lock()
        defer { lock.unlock() }
        let stats = backend?.statsSnapshot
        return (releasedCoreML + (stats?.coreMLChunks ?? 0), releasedFallback + (stats?.fallbackChunks ?? 0))
    }

    /// Đường của trình đọc lúc này — cho dòng log "tiếng đầu".
    var flowName: String {
        lock.lock()
        defer { lock.unlock() }
        if let disabledReason { return "ort (\(disabledReason))" }
        return backend == nil ? "ort (Core ML chưa sẵn sàng)" : "coreml"
    }

    private func accumulateLocked() {
        guard let stats = backend?.statsSnapshot else { return }
        releasedCoreML += stats.coreMLChunks
        releasedFallback += stats.fallbackChunks
    }
}
