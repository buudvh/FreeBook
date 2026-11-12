import Foundation

/// Lượt **Nano** của chế độ "Đọc liên tục": dựng lại session ORT theo số luồng + QoS chọn ở màn thử, đọc phân rã thời
/// gian từng đoạn, và trả engine về cấu hình của người dùng khi xong (1.3.878 — tách khỏi `+Run`).
extension VieNeuTurboLab {
    /// Nano qua đúng API một đoạn của nó (`VieNeuTTSService.synthesizeWithDuration`). Service tự chạy lớp số/ngày +
    /// tiếng Nhật, nên chỉ đưa chữ đã thay thế ký tự (giống Turbo nhận trước khi tự tiền xử lý).
    func makeNanoSynthesizer() async throws -> (String, VieNeuTurboSoakRunner.Synthesizer) {
        guard let service = VieNeuTTSService.shared, service.modelStore.isReady else {
            throw TTSError.modelNotCached("Chưa tải model VieNeu Nano — tải ở màn Cài đặt VieNeu TTS.")
        }
        let voice = service.defaultVoiceName ?? (try? service.availableVoices().first?.name) ?? ""
        guard !voice.isEmpty else { throw TTSError.modelNotCached("Không đọc được danh sách giọng của Nano.") }
        // Nhả Turbo (~188 MB + bộ đệm ggml) trước khi đo Nano: bớt áp lực bộ nhớ khi session ORT của Nano cũng nằm trong
        // RAM, và cửa sổ CPU của Nano không lẫn gì của Turbo.
        await runtime.release()
        frontend?.unload()
        isRuntimeLoaded = false

        // Dựng lại session **trước** khi chạy (CPU của lượt nạp không lẫn vào phút đầu) và **ở đúng QoS đã chọn**: luồng
        // phụ của pool ORT sinh ra lúc dựng session, nên dựng ở mức nào thì pool chạy ở mức đó. Lượt tổng hợp chạy ở
        // cùng mức (`VieNeuTurboSoakRunner.start(priority:)`).
        let threads = Int32(nanoThreadCount)
        let qos = nanoQoS
        workingMessage = "Đang dựng session Nano (\(threads) luồng, QoS \(qos.rawValue))…"
        await service.setLabThreadOverride(threads)
        // Bật cờ **sau** khi đã ghi đè: rời màn trong lúc chờ thì `startSoak` vẫn gọi `endNanoOverride` (lệch thế hệ) và
        // lúc đó cờ đã bật ⇒ không sót ghi đè.
        isNanoOverrideActive = true
        try await service.prepare(voice: voice, priority: qos.priority)

        let synthesize: VieNeuTurboSoakRunner.Synthesizer = { text, boundaryKind in
            let cpuStarted = ProcessCPUClock.nowMs()
            // Tốc độ tổng hợp 1× (không theo cài đặt) — Turbo không có tốc độ tổng hợp, so phải cùng điều kiện. Khoá tổng
            // hợp ngẫu nhiên: văn bản lặp nhiều vòng, không để vòng sau dùng lại kết quả theo khoá tự sinh của service.
            let result = try await service.synthesizeWithDuration(
                text: text,
                voice: voice,
                speed: 1.0,
                boundaryKind: boundaryKind,
                priority: .demand,
                synthesisKey: UUID().uuidString
            )
            // Lượt vừa rồi là lượt duy nhất đang chạy (màn thử đã dừng TTS chính, bộ sinh chạy từng lượt một) ⇒
            // `lastTiming` là của đúng đoạn này.
            let timing = service.lastTiming
            return VieNeuTurboSoakRunner.ChunkAudio(
                wav: result.data,
                audioSeconds: result.pcmDuration,
                synthesisMs: result.synthesisMs,
                cpuMs: ProcessCPUClock.nowMs() - cpuStarted,
                phonemeCount: nil,
                split: VieNeuTurboSoakStats.StageSplit(
                    textMs: timing.text.wallMs,
                    vectorMs: timing.vector.wallMs,
                    codecMs: timing.codec.wallMs,
                    textCPUMs: timing.text.cpuMs,
                    vectorCPUMs: timing.vector.cpuMs,
                    codecCPUMs: timing.codec.cpuMs
                ),
                qosNote: "tổng hợp \(timing.synthesisQoS) · session \(timing.sessionQoS)"
            )
        }
        return (
            "Nano · chế độ \(service.currentMode.rawValue) · \(threads) luồng ORT · giọng \(voice) · QoS \(qos.rawValue)",
            synthesize
        )
    }

    /// Trả số luồng của engine Nano về theo cài đặt để lượt đọc truyện kế tiếp không mang cấu hình của màn thử. Gọi khi
    /// dừng, rời màn hoặc nạp lỗi.
    /// - Trình đọc đang ở **Nano** ⇒ dựng lại session ở `.utility`, đúng như lúc app nạp engine bình thường.
    /// - Trình đọc đang ở **Turbo** ⇒ **nhả** Nano (~280 MB): màn thử nạp nó chỉ để đo, hai model không nên cùng nằm
    ///   trong RAM (`VieNeuTTSService.releaseEngineRuntime`, chặn nên chạy nền).
    func endNanoOverride() {
        guard isNanoOverrideActive, let service = VieNeuTTSService.shared else { return }
        isNanoOverrideActive = false
        let voice = service.currentVoice ?? service.defaultVoiceName ?? ""
        let readerUsesNano = VieNeuModelChoice.current == .nano
        // Giữ lại Task: `readSampleOnce` / `startSoak` chờ nó xong rồi mới chạy (nó có thể chặn vài giây chờ đoạn Nano dở,
        // rồi nhả Turbo hoặc xoá ghi đè luồng — chạy chen vào lượt mới là hỏng lượt đó).
        nanoRestoreTask = Task {
            do {
                await service.setLabThreadOverride(nil)
                if readerUsesNano {
                    try await service.prepare(voice: voice)
                } else {
                    _ = await Task.detached(priority: .utility) { service.releaseEngineRuntime() }.value
                }
            } catch {
                AppLogger.shared.log("❌ [VieNeuTurbo] Dựng lại session Nano sau màn thử lỗi: \(error.localizedDescription)")
            }
        }
    }

    /// Phép thử P1 "So EP cho Nano": dừng mọi lượt đang chạy + TTS chính, nhả Turbo và engine Nano (~280 MB) để Core ML
    /// có chỗ biên dịch, rồi mới tính. Lượt đọc truyện kế tiếp tự nạp lại engine của nó.
    func startEPProbe() {
        guard !isBusy else { return }
        epProbe.start { [weak self] in
            guard let self else { return }
            stopSample()
            soak.stop(reason: "chạy So EP")
            takeOverAudio()
            await releaseTask?.value
            await nanoRestoreTask?.value
            await runtime.release()
            frontend?.unload()
            isRuntimeLoaded = false
            if let service = VieNeuTTSService.shared {
                _ = await Task.detached(priority: .utility) { service.releaseEngineRuntime() }.value
            }
        }
    }
}
