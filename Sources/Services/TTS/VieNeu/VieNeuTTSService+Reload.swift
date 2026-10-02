import Foundation

/// Nạp lại engine tại chỗ — phục vụ các cài đặt **chỉ có hiệu lực lúc tạo session ORT**
/// (số luồng tổng hợp; trước 1.3.469 là công tắc CoreML EP đã bị loại).
///
/// Tách khỏi `VieNeuTTSService.swift` vì file đó chỉ còn **2 dòng** tới trần 400 của
/// `check_architecture.py`. Việc tách kéo theo một hệ quả bắt buộc: `engine` phải hạ `private` →
/// `internal` (Swift giới hạn `private` theo file), cùng khuôn với `VieNeuTTSEngine+Reload`.
extension VieNeuTTSService {
    /// Nhả ngữ cảnh ORT rồi nạp lại theo cấu hình **đang lưu**, giữ nguyên cài đặt chất lượng của người dùng.
    ///
    /// ## Trình tự bắt buộc
    /// 1. Bên gọi ghi `UserDefaults` **trước** (số luồng…), vì `engine.prepare()` đọc ở thời điểm nó chạy.
    /// 2. `engine.unload()` — nhả 4 session + phonemizer. Hàm này chờ lượt tổng hợp đang chạy xong nhờ
    ///    chính `lock` của engine (xem doc `VieNeuTTSEngine+Reload`).
    /// 3. `engine.prepare()` — dựng lại ngữ cảnh với cấu hình mới.
    /// 4. Áp lại `powerSaving`/`preferredMode` — y hệt `prepare(voice:)`, vì engine vừa được dựng mới và
    ///    `setRequestedMode` là thứ duy nhất giữ lựa chọn chất lượng sống qua lần nạp lại.
    ///
    /// Chạy trong `Task.detached(priority: .utility)` như `prepare(voice:)`: đọc 4 graph (~280 MB) là việc
    /// nặng và đồng bộ. **Không** được gọi khi đang đọc truyện — màn Cài đặt đã `prepareForSettings()` tạm
    /// dừng phát; phần bỏ đệm cũ do `TTSManager.invalidateVieNeuPrefetch(reason:)` lo sau khi nạp xong.
    ///
    /// Lỗi (model thiếu file, không tạo được session…) được **ném lên nguyên vẹn** để tầng UI báo toast —
    /// hàm này cố ý **không** tự nuốt lỗi.
    func reloadEngine(reason: String) async throws {
        let engine = self.engine
        let started = ProcessInfo.processInfo.systemUptime
        try await Task.detached(priority: .utility) {
            engine.unload()
            try engine.prepare()
        }.value
        engine.setRequestedMode(powerSaving ? .fast : preferredMode)
        AppLogger.shared.log("[TTSRoute] nap lai engine VieNeu reason=\(reason) trong \((ProcessInfo.processInfo.systemUptime - started) * 1000)ms")
    }
}
