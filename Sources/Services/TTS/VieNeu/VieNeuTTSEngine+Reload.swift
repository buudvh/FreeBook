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
    func withSynthesisLock(_ body: () throws -> Void) throws {
        lock.lock()
        defer { lock.unlock() }
        try body()
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
