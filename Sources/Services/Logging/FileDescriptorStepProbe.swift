import Foundation
import Darwin

/// Khoanh vùng chỗ rò fd lúc app ở nền.
///
/// Log 103 (bản 1.3.520): fd chỉ tăng khi app **ở nền** và đang phát TTS, khoảng một đợt mỗi đoạn audio; mỗi
/// đợt mở lại (chỉ đọc, không đọc byte nào) đúng một fd cho mỗi file trong một nhóm — `app_logs.txt`, `.bin`,
/// cả file hệ thống. Code app không làm việc đó, nên enum này đo xem đợt mở xảy ra **trong** bước nào của một
/// đoạn audio, hay **giữa** các bước (do thứ khác trong tiến trình đẩy vào):
///
/// - `measure`/`measureAsync` bọc một bước (gọi Google TTS, tạo `AVAudioPlayer`, `play()`, Now Playing…):
///   đếm fd trước/sau, tăng thì ghi `[FD] step=<bước> +N total=T chunk=C`.
/// - Nhịp 1 giây trong `tickWindowSeconds` đầu sau khi xuống nền: tổng đổi thì ghi `[FD] tick t=…s ±N total=T chunk=C`.
/// - Chỉ đo trong `measuredChunkLimit` đoạn audio đầu sau mỗi lần xuống nền, tối đa `stepLogBudget` dòng `step`;
///   ngoài khoảng đó `measure` chỉ gọi thẳng `body`. Đếm bằng `fcntl` tới fd lớn nhất từng thấy + biên, không mở fd mới.
enum FileDescriptorStepProbe {
    /// Bảo vệ mọi trạng thái bên dưới: `measure` chạy trên main, Google TTS trên luồng nền, nhịp trên `tickQueue`.
    private static let lock = NSLock()
    private static var isBackground = false
    private static var chunkIndex = 0
    private static var remainingStepLogs = 0
    /// Quét `0..<scanLimit`; 0 = chưa biết, quét tới giới hạn mềm.
    private static var scanLimit: Int32 = 0
    /// Ba biến dưới chỉ đổi trên `tickQueue`.
    private static var tickTimer: DispatchSourceTimer?
    private static var tickStartedAt: TimeInterval = 0
    private static var lastTickTotal = 0
    private static let tickQueue = DispatchQueue(label: "FreeBook.FileDescriptorStepProbe", qos: .utility)

    private static let measuredChunkLimit = 60
    private static let stepLogBudget = 40
    private static let tickWindowSeconds = 120
    /// Quét dư bấy nhiêu số fd trên fd lớn nhất từng thấy (fd mới luôn lấy số trống nhỏ nhất).
    private static let scanMargin: Int32 = 512
    private static let scanCap: Int32 = 16_384

    // MARK: - Điểm gọi

    /// App xuống nền / trở lại — gọi từ `FileDescriptorCensus.record(event:)` với `"background"`/`"active"`.
    static func noteScene(background: Bool) {
        lock.lock()
        if background && !isBackground {
            chunkIndex = 0
            remainingStepLogs = stepLogBudget
        }
        isBackground = background
        lock.unlock()
        tickQueue.async {
            if background {
                startTicks()
            } else {
                stopTicks()
            }
        }
    }

    /// Một đoạn audio bắt đầu phát — gọi từ `FileDescriptorCensus.tickChunk()`.
    static func noteChunk() {
        lock.lock()
        if isBackground { chunkIndex += 1 }
        lock.unlock()
    }

    static func measure<T>(_ step: String, _ body: () throws -> T) rethrows -> T {
        guard isMeasuring() else { return try body() }
        let before = countOpen()
        defer { report(step: step, before: before) }
        return try body()
    }

    static func measureAsync<T>(_ step: String, _ body: () async throws -> T) async rethrows -> T {
        guard isMeasuring() else { return try await body() }
        let before = countOpen()
        defer { report(step: step, before: before) }
        return try await body()
    }

    // MARK: - Đo

    private static func isMeasuring() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isBackground && chunkIndex <= measuredChunkLimit && remainingStepLogs > 0
    }

    private static func report(step: String, before: Int) {
        let after = countOpen()
        guard after > before else { return }
        lock.lock()
        guard remainingStepLogs > 0 else {
            lock.unlock()
            return
        }
        remainingStepLogs -= 1
        let chunk = chunkIndex
        lock.unlock()
        AppLogger.shared.logAlways("[FD] step=\(step) +\(after - before) total=\(after) chunk=\(chunk)")
    }

    /// Chỉ gọi trên `tickQueue`.
    private static func startTicks() {
        guard tickTimer == nil else { return }
        tickStartedAt = ProcessInfo.processInfo.systemUptime
        lastTickTotal = countOpen()
        AppLogger.shared.logAlways("[FD] probe start total=\(lastTickTotal)")
        let timer = DispatchSource.makeTimerSource(queue: tickQueue)
        timer.schedule(deadline: .now() + 1, repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler {
            let elapsed = Int(ProcessInfo.processInfo.systemUptime - tickStartedAt)
            guard elapsed <= tickWindowSeconds else {
                stopTicks()
                return
            }
            let total = countOpen()
            guard total != lastTickTotal else { return }
            lock.lock()
            let chunk = chunkIndex
            lock.unlock()
            let delta = total - lastTickTotal
            AppLogger.shared.logAlways("[FD] tick t=\(elapsed)s \(delta > 0 ? "+" : "")\(delta) total=\(total) chunk=\(chunk)")
            lastTickTotal = total
        }
        tickTimer = timer
        timer.resume()
    }

    /// Chỉ gọi trên `tickQueue`.
    private static func stopTicks() {
        tickTimer?.cancel()
        tickTimer = nil
    }

    /// Số fd đang mở. Chỉ quét tới fd lớn nhất từng thấy + `scanMargin` (lần đầu quét tới giới hạn mềm),
    /// nên rẻ khi bảng fd còn nhỏ.
    private static func countOpen() -> Int {
        var limit = rlimit()
        let soft = getrlimit(RLIMIT_NOFILE, &limit) == 0 ? Int32(min(limit.rlim_cur, rlim_t(scanCap))) : 256
        lock.lock()
        let known = scanLimit
        lock.unlock()
        let bound = known == 0 ? soft : min(known, soft)
        var count = 0
        var highest: Int32 = -1
        var fd: Int32 = 0
        while fd < bound {
            if fcntl(fd, F_GETFD) != -1 {
                count += 1
                highest = fd
            }
            fd += 1
        }
        lock.lock()
        scanLimit = max(scanLimit, min(soft, highest + scanMargin))
        lock.unlock()
        return count
    }
}
