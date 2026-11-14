import Foundation
#if canImport(AudioCpp)
import AudioCpp
#endif

// Dựng session audio.cpp của Turbo — tách khỏi `VieNeuTurboRuntime.swift` (trần 400 dòng). Chỉ chạm trong `queue`.
#if canImport(AudioCpp)
extension VieNeuTurboRuntime {
    /// Nhả session cũ (kèm mọi graph + bộ đệm audio.cpp giữ trong nó) rồi dựng session CPU mới. Trả ms dựng.
    ///
    /// AMX luôn bật từ 1.3.928 (`VieNeuTurboAcceleration.isAMXEnabled`, chỉ tắt khi bản build này từng sập giữa lượt
    /// AMX): session option `vieneu_v3_turbo.codec_blas=true` + `vieneu_v3_turbo.prefill_blas=true` (bản vá
    /// `vieneu_codec_blas`, `vieneu_prefill_blas`) + `vieneu_v3_turbo.threadpool_poll=0` (1.3.929, `vieneu_threadpool`:
    /// pool luồng giữ suốt session) + `vieneu_v3_turbo.acoustic_repack=true` (1.3.930, `vieneu_acoustic_repack`).
    /// Tắt ⇒ không truyền option nào, y như trước 1.3.924.
    /// Gọi từ `prepareLocked` (lần đầu, đổi số luồng, AMX vừa bị tự tắt), từ lượt thử lại sau lỗi cấp phát và từ
    /// `VieNeuTurboRuntime+Encode` (dựng lại sau khi mã hoá giọng mẫu).
    @discardableResult
    func createSessionLocked(threads: Int) throws -> Double {
        audiocpp_session_free(session)
        session = nil
        sessionThreads = 0
        sessionCodecBLAS = false
        // Lần trước chết giữa lượt AMX ⇒ tự tắt AMX cho bản build này TRƯỚC khi đọc cờ; đặt file nhận câu báo của ggml.
        VieNeuTurboCrashGuard.recoverIfNeeded()
        VieNeuTurboCrashGuard.installAbortNote()
        // Thư mục của màn đo tạm codec AMX vs Neural Engine (1.3.932, gỡ ở 1.3.933): ~45 MB ONNX + cache Core ML còn lại
        // trên máy đã chạy màn đo. Xoá được dòng này sau vài bản.
        try? FileManager.default.removeItem(
            at: FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("turbo-codec-bench", isDirectory: true)
        )
        let codecBLAS = VieNeuTurboAcceleration.isAMXEnabled
        let options = codecBLAS ? audiocpp_options_create() : nil
        defer { audiocpp_options_free(options) }
        if let options {
            // Codec + bước nạp prompt cùng qua Accelerate — log tách từng phần (`codecMs`, `prefillMs`, `amx=`).
            // + trọng số bộ giải mã âm học trong bộ đệm CPU_REPACK (1.3.930, log `repack=`).
            for option in [
                VieNeuTurboAcceleration.codecBLASOption,
                VieNeuTurboAcceleration.prefillBLASOption,
                VieNeuTurboAcceleration.acousticRepackOption
            ] {
                try Self.check(audiocpp_options_set(options, option, "true"), "audiocpp_options_set(\(option))")
            }
            // Pool luồng giữ suốt session — đi chung cờ AMX để lối tự tắt khi sập tắt luôn.
            let poolOption = VieNeuTurboAcceleration.threadpoolPollOption
            try Self.check(
                audiocpp_options_set(options, poolOption, VieNeuTurboAcceleration.threadpoolPoll),
                "audiocpp_options_set(\(poolOption))"
            )
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
            "🎙️ [VieNeuTurbo] Dựng session CPU \(threads) luồng, AMX (codec + nạp prompt) + pool luồng + repack âm học "
                + "\(codecBLAS ? "bật" : "tắt"): "
                + "\(String(format: "%.0f", createMs)) ms — \(ProcessMemoryProbe.snapshot().summary)"
        )
        return createMs
    }
}
#endif
