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
        let defaults = UserDefaults.standard
        let wantedThreads = VieNeuSynthesisPolicy.effectiveThreadCount(from: defaults)
        let wantedSpinning = VieNeuSynthesisPolicy.allowSpinning(from: defaults)
        guard current.threadCount != wantedThreads || current.allowSpinning != wantedSpinning else { return false }
        AppLogger.shared.log(
            "🎙️ [VieNeu] Cài đặt đổi (threads \(current.threadCount)→\(wantedThreads), spin "
                + "\(current.allowSpinning ? "on" : "off")→\(wantedSpinning ? "on" : "off")) — nạp lại engine"
        )
        runtime = nil
        return true
    }
}
