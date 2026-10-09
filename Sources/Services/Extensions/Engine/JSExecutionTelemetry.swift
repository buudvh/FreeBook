import Foundation

/// Đo **chỉ để ghi log** — không đổi hành vi (plan `Docs/Plans/2026-10-09-plan-perf-4-hotspots.md` §1.3).
///
/// `JSExecutor.callAsync` là hàm `async` nonisolated (Swift 5 mode, SE-0338) nên luôn chạy trên thread của
/// cooperative pool — **không bao giờ** trên main — và gọi `runner.call` **đồng bộ** ở đó: suốt lúc script
/// `fetch`/`sleep`/chờ browser, thread ấy bị chặn cứng. Bộ đếm này trả lời đúng một câu: có lúc nào số lời
/// gọi đồng bộ đang chạy cùng lúc chạm `activeProcessorCount` (pool cạn theo định nghĩa) hay không. Hậu quả
/// lên TTS thì đọc ở log có sẵn `[TTSPerf] PrefetchSummary` (`waitedHit`/`miss`/`maxWaitMs`).
///
/// Chỉ ghi khi **có chồng lấn**, để Ext TTS từng chunk hay tải tuần tự từng chương (một lời gọi mỗi lúc)
/// không sinh log: `SyncCall` cho lời gọi bắt đầu lúc đã có lời gọi khác chạy; `SyncBurst` khi một đợt
/// chồng lấn (đỉnh ≥ 2) kết thúc.
enum JSExecutionTelemetry {
    struct Token {
        fileprivate let startedAt: CFAbsoluteTime
        fileprivate let concurrentAtStart: Int
    }

    private static let lock = NSLock()
    private static var inFlight = 0
    private static var burstPeak = 0
    private static var burstCalls = 0
    private static var burstStartedAt: CFAbsoluteTime = 0

    static func begin() -> Token {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        if inFlight == 0 {
            burstPeak = 0
            burstCalls = 0
            burstStartedAt = now
        }
        inFlight += 1
        burstCalls += 1
        burstPeak = max(burstPeak, inFlight)
        let concurrent = inFlight
        lock.unlock()
        return Token(startedAt: now, concurrentAtStart: concurrent)
    }

    static func end(_ token: Token, localPath: String?, functionName: String) {
        let now = CFAbsoluteTimeGetCurrent()
        lock.lock()
        inFlight -= 1
        let burstEnded = inFlight == 0
        let peak = burstPeak
        let calls = burstCalls
        let burstMs = (now - burstStartedAt) * 1000.0
        lock.unlock()

        let cores = ProcessInfo.processInfo.activeProcessorCount
        if token.concurrentAtStart >= 2 {
            let source = localPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "-"
            AppLogger.shared.log(String(
                format: "[JSPerf] SyncCall source=%@ fn=%@ ms=%.1f concurrent=%d cores=%d",
                source, functionName, (now - token.startedAt) * 1000.0, token.concurrentAtStart, cores
            ))
        }
        if burstEnded && peak >= 2 {
            AppLogger.shared.log(String(
                format: "[JSPerf] SyncBurst peak=%d calls=%d ms=%.1f cores=%d saturated=%d",
                peak, calls, burstMs, cores, peak >= cores ? 1 : 0
            ))
        }
    }
}
