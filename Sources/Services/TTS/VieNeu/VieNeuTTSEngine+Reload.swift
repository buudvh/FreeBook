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
        let forced = labForceReload
        labForceReload = false // xoá cả khi chưa có runtime, kẻo lượt sau dựng lại lần nữa vô cớ
        guard let current = runtime else { return true }
        if forced {
            AppLogger.shared.log("🎙️ [VieNeu] Màn thử đổi cấu hình (threads \(wantedThreadCountLocked())) — dựng lại session")
            runtime = nil
            return true
        }
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

    /// Số luồng ORT muốn dùng: ghi đè của màn thử nếu có, không thì theo cài đặt. **Chỉ gọi khi đang giữ `lock`.**
    func wantedThreadCountLocked() -> Int32 {
        labThreadOverride ?? VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
    }

    /// Màn thử VieNeu Turbo đặt / bỏ số luồng ORT riêng (1.3.849) — **không** ghi vào cài đặt của người dùng.
    ///
    /// Đặt hay bỏ đều buộc dựng lại session ở lần nạp kế tiếp. Luồng phụ của pool ORT sinh ra lúc dựng session nên mang
    /// QoS của luồng đang dựng; màn thử dựng ngay ở QoS mình chọn (`VieNeuTTSService.prepare(voice:priority:)`), và khi
    /// bỏ ghi đè thì dựng lại ở mức của trình đọc (`VieNeuTTSService.readerPriority`) như lúc app nạp engine bình thường.
    func setLabThreadOverride(_ threads: Int32?) {
        lock.lock(); defer { lock.unlock() }
        labThreadOverride = threads.map { max(1, $0) }
        labForceReload = true
    }
}
