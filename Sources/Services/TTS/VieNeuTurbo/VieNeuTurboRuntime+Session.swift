import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

// Dựng session audio.cpp của Turbo — tách khỏi `VieNeuTurboRuntime.swift` (trần 400 dòng). Chỉ chạm trong `queue`.
#if canImport(AudioCpp)
extension VieNeuTurboRuntime {
    /// Nhả session cũ (kèm mọi graph + bộ đệm audio.cpp giữ trong nó) rồi dựng session CPU mới. Trả ms dựng.
    ///
    /// Đọc công tắc "Tăng tốc bằng AMX" **lúc dựng** (`VieNeuTurboAcceleration`): bật ⇒ session option
    /// `vieneu_v3_turbo.codec_blas=true` + `vieneu_v3_turbo.prefill_blas=true` (bản vá `vieneu_codec_blas`,
    /// `vieneu_prefill_blas`). Tắt ⇒ không truyền option nào, y như trước 1.3.924.
    /// Gọi từ `prepareLocked` (lần đầu, đổi số luồng, đổi công tắc), từ lượt thử lại sau lỗi cấp phát và từ
    /// `VieNeuTurboRuntime+Encode` (dựng lại sau khi mã hoá giọng mẫu).
    @discardableResult
    func createSessionLocked(threads: Int) throws -> Double {
        audiocpp_session_free(session)
        session = nil
        sessionThreads = 0
        sessionCodecBLAS = false
        // Lần trước chết giữa lượt AMX ⇒ tự tắt công tắc TRƯỚC khi đọc nó; đặt file nhận câu báo của ggml (1.3.925).
        VieNeuTurboCrashGuard.recoverIfNeeded()
        VieNeuTurboCrashGuard.installAbortNote()
        let codecBLAS = VieNeuTurboAcceleration.isCodecAMXEnabled
        let options = codecBLAS ? audiocpp_options_create() : nil
        defer { audiocpp_options_free(options) }
        if let options {
            // Một công tắc bật cả codec lẫn bước nạp prompt (1.3.927) — log tách từng phần nên vẫn so được riêng.
            for option in [VieNeuTurboAcceleration.codecBLASOption, VieNeuTurboAcceleration.prefillBLASOption] {
                try Self.check(audiocpp_options_set(options, option, "true"), "audiocpp_options_set(\(option))")
            }
        }
        let started = ProcessInfo.processInfo.systemUptime
        var created: OpaquePointer?
        let status: audiocpp_status = "cpu".withCString { backendName in
            var backend = audiocpp_backend_config(backend: backendName, device: 0, threads: Int32(threads))
            return audiocpp_session_create(model, "tts", "offline", &backend, options, &created)
        }
        try Self.check(status, "audiocpp_session_create")
        session = created
        sessionThreads = threads
        sessionCodecBLAS = codecBLAS
        let createMs = Self.elapsedMs(since: started)
        AppLogger.shared.log(
            "🎙️ [VieNeuTurbo] Dựng session CPU \(threads) luồng, AMX (codec + nạp prompt) \(codecBLAS ? "bật" : "tắt"): "
                + "\(String(format: "%.0f", createMs)) ms — \(ProcessMemoryProbe.snapshot().summary)"
        )
        return createMs
    }
}
#endif
