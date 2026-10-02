import Foundation

/// Nạp lại engine tại chỗ — phục vụ công tắc **"Dùng CoreML/ANE (thử nghiệm)"** (1.3.466).
///
/// Tách khỏi `VieNeuTTSService.swift` vì file đó chỉ còn **2 dòng** tới trần 400 của
/// `check_architecture.py`. Việc tách kéo theo một hệ quả bắt buộc: `engine` phải hạ `private` →
/// `internal` (Swift giới hạn `private` theo file), cùng khuôn với `VieNeuTTSEngine+Reload`.
extension VieNeuTTSService {
    /// Nhả ngữ cảnh ORT rồi nạp lại theo `useCoreML`, giữ nguyên cài đặt chất lượng của người dùng.
    ///
    /// ## Trình tự bắt buộc
    /// 1. Ghi khoá `vieneuCoreMLEP` **trước** — vì `engine.prepare()` đọc `UserDefaults` ở thời điểm nó
    ///    chạy, nên ghi sau là nạp lại bằng cấu hình cũ.
    /// 2. `engine.unload()` — nhả 4 session + phonemizer. Hàm này chờ lượt tổng hợp đang chạy xong nhờ
    ///    chính `lock` của engine (xem doc `VieNeuTTSEngine+Reload`).
    /// 3. `engine.prepare()` — dựng lại ngữ cảnh, lần này kèm CoreML EP nếu cờ bật.
    /// 4. Áp lại `powerSaving`/`preferredMode` — y hệt `prepare(voice:)`, vì engine vừa được dựng mới và
    ///    `setRequestedMode` là thứ duy nhất giữ lựa chọn chất lượng sống qua lần nạp lại.
    ///
    /// Chạy trong `Task.detached(priority: .utility)` như `prepare(voice:)`: đọc 4 graph (~280 MB) là việc
    /// nặng và đồng bộ. **Không** được gọi khi đang đọc truyện — màn Cài đặt đã `prepareForSettings()` tạm
    /// dừng phát; phần bỏ đệm cũ do `TTSManager.invalidateVieNeuPrefetch(reason:)` lo sau khi nạp xong.
    ///
    /// Lỗi (EP không đăng ký được, model thiếu file…) được **ném lên nguyên vẹn** để tầng UI tự quay về
    /// CPU và báo toast — hàm này cố ý **không** tự nuốt lỗi.
    func reloadEngine(useCoreML: Bool) async throws {
        UserDefaults.standard.set(useCoreML, forKey: VieNeuSynthesisPolicy.coreMLEPKey)
        let engine = self.engine
        let started = ProcessInfo.processInfo.systemUptime
        try await Task.detached(priority: .utility) {
            engine.unload()
            try engine.prepare()
        }.value
        engine.setRequestedMode(powerSaving ? .fast : preferredMode)
        AppLogger.shared.log("[TTSRoute] nap lai engine VieNeu coreML=\(useCoreML) trong \((ProcessInfo.processInfo.systemUptime - started) * 1000)ms")
    }

    /// `true` khi engine **đang dùng** đã đăng ký được CoreML EP — nguồn sự thật cho UI.
    ///
    /// Khác `UserDefaults`: cờ cài đặt chỉ là *ý định*, còn giá trị này nói EP có thật sự vào được hay
    /// `VieNeuONNXRuntime.init` đã tự quay về CPU.
    var isCoreMLActive: Bool { engine.coreMLActive }
}
