import Foundation

extension VieNeuTTSEngine {
    /// `true` ⇒ phải nạp (lại) engine. **Chỉ gọi khi đang giữ `lock`** (từ `prepareLocked`).
    ///
    /// Số luồng ORT và spin chỉ đặt được lúc dựng session, mà engine là singleton không tự unload ⇒ trước
    /// 1.3.500 muốn đổi phải tắt hẳn app. Nay mỗi lượt tổng hợp so cấu hình của runtime **đang chạy** với cài
    /// đặt hiện tại (gồm cả "Tiết kiệm pin" ghim 2 luồng); lệch thì bỏ runtime cũ để `prepareLocked` nạp lại
    /// ngay lượt này (~3 s). Runtime cũ bị giải phóng (session + tensor cache, `VieNeuORTDestroy`) **trước**
    /// khi dựng cái mới ⇒ không nhân đôi bộ nhớ, và không cache nào còn trỏ vào `nullContext` cũ khi nó bị gán lại.
    func runtimeNeedsLoadLocked() -> Bool {
        guard let current = runtime else { return true }
        let wantedThreads = wantedThreadCountLocked()
        let wantedSpinning = VieNeuSynthesisPolicy.allowSpinning(from: .standard)
        guard current.threadCount != wantedThreads || current.allowSpinning != wantedSpinning else { return false }
        AppLogger.shared.log(
            "🎙️ [VieNeu] Cài đặt đổi (threads \(current.threadCount)→\(wantedThreads), spin "
                + "\(current.allowSpinning ? "on" : "off")→\(wantedSpinning ? "on" : "off")) — nạp lại engine"
        )
        runtime = nil
        return true
    }

    /// Chạy `body` trong khoá tổng hợp (P2c): nạp + chạy nháp Core ML của trình đọc không chồng lên lượt đang đọc —
    /// session ORT / Core ML không chịu hai luồng gọi cùng lúc. Giữ khoá ngắn (một khung mỗi lần).
    ///
    /// **Nhường lượt đọc** (1.3.955): chỉ lấy khoá khi khoá đang rảnh và không lượt đọc / nạp engine nào xếp hàng
    /// (`lockForReader`). `NSLock` không xếp hàng công bằng — luồng chạy nháp nhả khoá rồi lấy lại ngay ở khung kế nên
    /// thắng luồng đang chờ, giữ khoá liền cả 5 khung (log build 1283: 4 s không lượt tổng hợp nào chen vào được). Lượt đọc
    /// tới giữa một khung chỉ chờ hết khung đó.
    ///
    /// Chờ bằng **tín hiệu** (1.3.961): lượt đọc nhả khoá (`unlockForReader`) thì đánh thức luồng chạy nháp. Trước đó luồng
    /// này hỏi lại mỗi 10 ms — trong lúc Nano đọc liên tục là ~100 lần đánh thức CPU mỗi giây. Bên giữ khoá khác (nhả engine,
    /// danh mục giọng…) không báo, nên chờ có hạn `fallbackWait` rồi tự hỏi lại.
    func withSynthesisLock(_ body: () throws -> Void) throws {
        readerWaitLock.lock()
        while !(waitingReaders == 0 && lock.try()) {
            _ = readerWaitLock.wait(until: Date(timeIntervalSinceNow: Self.warmUpFallbackWait))
        }
        readerWaitLock.unlock()
        defer { lock.unlock() }
        try body()
    }

    /// Hạn chờ của `withSynthesisLock` khi không ai báo (bên giữ khoá không phải lượt đọc).
    private static let warmUpFallbackWait: TimeInterval = 0.1

    /// Lấy `lock` cho một lượt **đọc / nạp engine** (`synthesize`, `prepare`), có đếm "đang chờ" để lượt chạy nháp Core ML
    /// nhường (`withSynthesisLock`). Bên gọi nhả bằng `unlockForReader()`.
    func lockForReader() {
        readerWaitLock.lock()
        waitingReaders += 1
        readerWaitLock.unlock()
        lock.lock()
        readerWaitLock.lock()
        waitingReaders -= 1
        readerWaitLock.unlock()
    }

    /// Nhả `lock` của lượt đọc rồi đánh thức lượt chạy nháp đang chờ (`withSynthesisLock`).
    func unlockForReader() {
        lock.unlock()
        readerWaitLock.lock()
        readerWaitLock.broadcast()
        readerWaitLock.unlock()
    }

    /// Nhả 4 session ORT (~280 MB, `VieNeuORTDestroy` ở `deinit` của runtime) + bộ phiên âm của Nano khi trình đọc chuyển
    /// sang Turbo — hai model không nên cùng nằm trong RAM. Lượt Nano sau tự nạp lại (`prepareLocked` thấy `runtime == nil`).
    ///
    /// **Chặn** tới khi lượt Nano đang chạy (nếu có) nhả `lock` ⇒ đừng gọi trên main. Trả `true` khi thật sự có thứ để nhả.
    @discardableResult
    func releaseRuntime() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard runtime != nil else { return false }
        runtime = nil
        phonemizer = nil
        return true
    }

    /// Số luồng ORT muốn dùng (theo cài đặt). **Chỉ gọi khi đang giữ `lock`.**
    func wantedThreadCountLocked() -> Int32 {
        VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
    }
}
