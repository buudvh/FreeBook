import AVFoundation
import Foundation

/// Phần **chạy** của `VieNeuTurboLab`: đọc thử một lần, đọc liên tục (Turbo hoặc Nano), giành / trả phiên âm thanh.
extension VieNeuTurboLab {
    var canRunTurbo: Bool {
        VieNeuTurboRuntime.isAvailable && isTurboReady && !selectedVoiceId.isEmpty && !isBusy
    }

    /// Nano so được khi đã tải đủ 8 file của nó (màn "Cài đặt VieNeu TTS").
    var isNanoReady: Bool {
        VieNeuTTSService.shared?.modelStore.isReady ?? false
    }

    var canStartSoak: Bool {
        guard !isBusy else { return false }
        switch soakEngine {
        case .turbo: return canRunTurbo
        case .nano: return isNanoReady
        }
    }

    // MARK: - Đọc thử một lần

    /// Tổng hợp **cả đoạn** trong một lượt `audiocpp_session_run` (audio.cpp tự cắt chunk và chèn khoảng nghỉ), phát, rồi
    /// báo: thời gian nạp model (lần đầu), thời gian tổng hợp, độ dài tiếng, RTF, CPU-s mỗi giây tiếng, nhiệt.
    func readSampleOnce() {
        guard canRunTurbo, let store, let frontend else { return }
        stopSample()
        let processed = TTSReplacementManager.shared.applyReplacements(to: text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !processed.isEmpty else {
            isError = true
            statusMessage = "Không còn chữ để đọc sau khi áp quy tắc thay thế ký tự."
            return
        }
        takeOverAudio()
        let voiceId = selectedVoiceId
        let threads = threadCount
        runGeneration += 1
        let generation = runGeneration
        isWorking = true
        isError = false
        statusMessage = ""
        lastReport = ""
        oneShotTask = Task { [weak self] in
            guard let self else { return }
            defer { if generation == runGeneration { isWorking = false } }
            do {
                await releaseTask?.value
                await nanoRestoreTask?.value
                try await ensureVoice(voiceId)
                workingMessage = isRuntimeLoaded ? "Đang dựng session…" : "Đang nạp model Turbo (lần đầu)…"
                let load = try await runtime.prepare(modelURL: store.modelURL, threads: threads)
                isRuntimeLoaded = true
                guard generation == runGeneration else { return }

                workingMessage = "Đang tổng hợp…"
                let thermalBefore = ProcessInfo.processInfo.thermalState
                let wallStarted = ProcessInfo.processInfo.systemUptime
                let cpuStarted = ProcessCPUClock.nowMs()
                let prepared = try await frontend.prepare(processed)
                let output = try await runtime.synthesize(
                    phonemes: prepared.phonemes,
                    referenceCodesURL: store.referenceCodesURL(voiceId: voiceId),
                    speakerEmbeddingURL: store.speakerEmbeddingURL(voiceId: voiceId),
                    qos: turboQoS.dispatchClass
                )
                let cpuMs = ProcessCPUClock.nowMs() - cpuStarted
                let totalMs = (ProcessInfo.processInfo.systemUptime - wallStarted) * 1_000
                guard generation == runGeneration else { return }

                let wav = WAVEncoder.encodePCM16(samples: output.samples, sampleRate: output.sampleRate, channels: 1)
                presentSampleReport(
                    load: load,
                    characters: processed.count,
                    prepared: prepared,
                    output: output,
                    cpuMs: cpuMs,
                    totalMs: totalMs,
                    thermalBefore: thermalBefore
                )
                playSample(wav)
            } catch {
                guard generation == runGeneration else { return }
                isError = true
                statusMessage = "Đọc thử thất bại: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuTurbo] Đọc thử lỗi: \(error.localizedDescription)")
            }
        }
    }

    private func presentSampleReport(
        load: VieNeuTurboRuntime.LoadReport,
        characters: Int,
        prepared: VieNeuTurboTextFrontend.Prepared,
        output: VieNeuTurboRuntime.Output,
        cpuMs: Double,
        totalMs: Double,
        thermalBefore: ProcessInfo.ThermalState
    ) {
        let audioSeconds = output.durationSeconds
        let thermalAfter = ProcessInfo.processInfo.thermalState
        let format = { (value: Double, digits: Int) in String(format: "%.\(digits)f", value) }
        let loadText = load.modelLoadMs.map { "\(format($0, 0)) ms" } ?? "đã nạp sẵn"
        let sessionText = load.sessionCreateMs.map { "\(format($0, 0)) ms" } ?? "dùng lại"
        statusMessage = "Xong: \(format(audioSeconds, 2)) giây tiếng, tổng hợp \(format(totalMs / 1_000, 2)) giây."
        lastReport = """
        luồng         \(load.threads) (CPU, QoS \(VieNeuTurboRuntime.qosName))
        nạp model     \(loadText)
        dựng session  \(sessionText)
        chữ / âm vị   \(characters) / \(prepared.phonemes.count) ký tự
        phiên âm      \(format(prepared.frontendMs, 0)) ms
        audio.cpp     \(format(output.runMs, 0)) ms
        độ dài tiếng  \(format(audioSeconds, 2)) s (\(output.sourceChannels) kênh → mono, \(output.sampleRate) Hz)
        RTF           \(VieNeuTurboSoakStats.ratio(totalMs / 1_000, audioSeconds))   (audio.cpp riêng: \(VieNeuTurboSoakStats.ratio(output.runMs / 1_000, audioSeconds)))
        CPU/tiếng     \(VieNeuTurboSoakStats.ratio(cpuMs / 1_000, audioSeconds))   (CPU-s mỗi giây tiếng, cả tiến trình)
        CPU trung bình \(format(cpuMs / max(totalMs, 1) * 100, 0))% một lõi
        nhiệt         \(VieNeuTurboSoakStats.thermalName(thermalBefore)) → \(VieNeuTurboSoakStats.thermalName(thermalAfter))
        thư viện      \(VieNeuTurboRuntime.versionDescription)
        """
        let loadField = load.modelLoadMs.map { format($0, 0) } ?? "-"
        let fields: [String] = [
            "threads=\(load.threads)",
            "chars=\(characters)",
            "phonemes=\(prepared.phonemes.count)",
            "loadMs=\(loadField)",
            "synthMs=\(format(totalMs, 0))",
            "runMs=\(format(output.runMs, 0))",
            "audio=\(format(audioSeconds, 2))s",
            "RTF=\(VieNeuTurboSoakStats.ratio(totalMs / 1_000, audioSeconds))",
            "cpuPerAudio=\(VieNeuTurboSoakStats.ratio(cpuMs / 1_000, audioSeconds))",
            "thermal=\(VieNeuTurboSoakStats.thermalName(thermalAfter))"
        ]
        AppLogger.shared.log("🎙️ [VieNeuTurbo] Đọc thử: " + fields.joined(separator: " "))
    }

    private func playSample(_ data: Data) {
        let fileManager = FileManager.default
        if let previous = lastAudioURL { try? fileManager.removeItem(at: previous) }
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("vieneu-turbo-\(Int(Date().timeIntervalSince1970)).wav")
        lastAudioURL = (try? data.write(to: url, options: .atomic)) != nil ? url : nil
        do {
            let newPlayer = try AVAudioPlayer(data: data)
            newPlayer.prepareToPlay()
            newPlayer.play()
            player = newPlayer
            hasSamplePlayer = true
            // Không cần delegate: hết thời lượng thì tự hạ cờ để nút "Dừng" đổi lại thành "Đọc thử".
            let generation = runGeneration
            let duration = newPlayer.duration
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration + 0.3))
                guard let self, generation == runGeneration else { return }
                hasSamplePlayer = false
            }
        } catch {
            isError = true
            statusMessage = "Phát thất bại: \(error.localizedDescription)"
        }
    }

    /// Dừng lượt đọc thử (và lượt đọc liên tục đang nạp model): bỏ kết quả của lượt đang tổng hợp — audio.cpp không huỷ
    /// được giữa chừng — và tắt tiếng.
    func stopSample() {
        runGeneration += 1
        oneShotTask?.cancel()
        oneShotTask = nil
        player?.stop()
        player = nil
        hasSamplePlayer = false
        isWorking = false
        isPreparingSoak = false
    }

    // MARK: - Đọc liên tục

    func startSoak() {
        guard canStartSoak else { return }
        let processed = TTSReplacementManager.shared.applyReplacements(to: longText)
        let chunks = VieNeuTurboSoakRunner.chunks(from: processed)
        guard !chunks.isEmpty else {
            isError = true
            statusMessage = "Văn bản dài trống sau khi áp quy tắc thay thế ký tự."
            return
        }
        stopSample()
        takeOverAudio()
        // Rời màn (`leaveScreen` ⇒ `stopSample`) trong lúc đang nạp model thì số thế hệ đổi ⇒ không bắt đầu nữa.
        let generation = runGeneration
        isWorking = true
        isPreparingSoak = true
        isError = false
        statusMessage = ""
        let engine = soakEngine
        // Lượt Nano chạy ở QoS chọn trên màn (session ORT cũng dựng lại ở mức đó — `+Nano`); Turbo giữ `.utility`.
        let priority = engine == .nano ? nanoQoS.priority : turboQoS.priority
        Task { [weak self] in
            guard let self else { return }
            do {
                await releaseTask?.value
                await nanoRestoreTask?.value
                let prepared: (String, VieNeuTurboSoakRunner.Synthesizer)
                if engine == .turbo {
                    prepared = try await makeTurboSynthesizer()
                } else {
                    prepared = try await makeNanoSynthesizer()
                }
                guard generation == runGeneration else {
                    endNanoOverride() // rời màn / bấm dừng lúc đang dựng session ⇒ trả số luồng như cũ
                    return
                }
                isWorking = false
                isPreparingSoak = false
                soak.start(chunks: chunks, engineDescription: prepared.0, priority: priority, synthesize: prepared.1)
            } catch {
                endNanoOverride()
                guard generation == runGeneration else { return }
                isWorking = false
                isPreparingSoak = false
                isError = true
                statusMessage = "Không bắt đầu được: \(error.localizedDescription)"
                AppLogger.shared.log("❌ [VieNeuTurbo] Không bắt đầu đọc liên tục (\(engine.rawValue)): \(error.localizedDescription)")
            }
        }
    }

    /// Dừng lượt đọc liên tục; đang nạp model thì huỷ luôn lượt sắp bắt đầu.
    func stopSoak() {
        if isPreparingSoak { stopSample() }
        soak.stop()
        endNanoOverride()
    }

    /// Nạp model + giọng **trước** khi chạy, để CPU của lượt nạp không lẫn vào phút đầu.
    private func makeTurboSynthesizer() async throws -> (String, VieNeuTurboSoakRunner.Synthesizer) {
        guard let store, let frontend else { throw VieNeuTurboRuntime.RuntimeError.notLoaded }
        let voiceId = selectedVoiceId
        let threads = threadCount
        try await ensureVoice(voiceId)
        workingMessage = isRuntimeLoaded ? "Đang dựng session…" : "Đang nạp model Turbo (lần đầu)…"
        _ = try await runtime.prepare(modelURL: store.modelURL, threads: threads)
        isRuntimeLoaded = true
        let runtime = self.runtime
        let referenceCodesURL = store.referenceCodesURL(voiceId: voiceId)
        let speakerEmbeddingURL = store.speakerEmbeddingURL(voiceId: voiceId)
        let qos = turboQoS
        let synthesize: VieNeuTurboSoakRunner.Synthesizer = { text, boundaryKind in
            let wallStarted = ProcessInfo.processInfo.systemUptime
            let cpuStarted = ProcessCPUClock.nowMs()
            let prepared = try await frontend.prepare(text)
            let output = try await runtime.synthesize(
                phonemes: prepared.phonemes,
                referenceCodesURL: referenceCodesURL,
                speakerEmbeddingURL: speakerEmbeddingURL,
                qos: qos.dispatchClass
            )
            // Khoảng nghỉ cuối đoạn đúng như engine Nano tự chèn (`VieNeuTTSEngine.pauseSeconds`, tốc độ 1×) — để "giây
            // tiếng" của hai engine cùng nghĩa khi so.
            var samples = output.samples
            let pause = VieNeuTTSEngine.pauseSeconds(for: boundaryKind)
            samples.append(contentsOf: [Float](repeating: 0, count: Int(Double(output.sampleRate) * pause)))
            let wav = WAVEncoder.encodePCM16(samples: samples, sampleRate: output.sampleRate, channels: 1)
            return VieNeuTurboSoakRunner.ChunkAudio(
                wav: wav,
                audioSeconds: Double(samples.count) / Double(max(1, output.sampleRate)),
                synthesisMs: (ProcessInfo.processInfo.systemUptime - wallStarted) * 1_000,
                cpuMs: ProcessCPUClock.nowMs() - cpuStarted,
                phonemeCount: prepared.phonemes.count,
                qosNote: "tổng hợp \(output.qosName)"
            )
        }
        let voiceName = selectedVoice?.name ?? voiceId
        return ("Turbo q8_0 · \(threads) luồng · giọng \(voiceName) · QoS \(qos.rawValue)", synthesize)
    }

    // MARK: - Phiên âm thanh / rời màn

    /// Dừng TTS chính nếu đang đọc (như `AudioPlaybackSession.stopTTSForMusic`) rồi giành `AVAudioSession` `.playback`.
    func takeOverAudio() {
        let tts = TTSManager.shared
        if tts.isPlaying || tts.showFloatingWidget {
            AppLogger.shared.log("⏹️ [VieNeuTurbo] Dừng TTS chính trước khi thử (đang đọc: \(tts.isPlaying ? "có" : "không"))")
            tts.stop()
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            didActivateAudioSession = true
        } catch {
            AppLogger.shared.log("❌ [VieNeuTurbo] Không giành được AVAudioSession: \(error.localizedDescription)")
        }
    }

    /// Rời màn thử: dừng mọi thứ, nhả model audio.cpp + `sea_g2p.bin`. Lượt tải đang chạy vẫn tiếp tục (singleton).
    ///
    /// Trình đọc đang chọn Turbo thì **giữ** model: runtime + bộ phiên âm dùng chung với nó, nhả là đoạn kế phải nạp lại.
    func leaveScreen() {
        soak.stop(reason: "rời màn thử")
        stopSample()
        endNanoOverride()
        let runtime = self.runtime
        let frontend = self.frontend
        let keepForReader = TTSManager.shared.tool == "vieneu" && VieNeuModelChoice.current == .turbo
        releaseTask = Task { [weak self] in
            if !keepForReader {
                await runtime.release()
                frontend?.unload()
            }
            guard let self else { return }
            isRuntimeLoaded = false
            releaseAudioSession()
            releaseTask = nil
        }
    }

    private func releaseAudioSession() {
        guard didActivateAudioSession else { return }
        didActivateAudioSession = false
        // Bên khác đang phát thì để nguyên phiên — họ đã cấu hình nó.
        guard !TTSManager.shared.isPlaying, !VideoNativePlaybackFlag.isPlaying, !AudioPlaybackFlag.isPlaying else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
