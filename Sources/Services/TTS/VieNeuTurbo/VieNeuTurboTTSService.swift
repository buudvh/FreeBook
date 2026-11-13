import Foundation

/// Trình đọc **VieNeu-TTS v3 Turbo** (GGUF q8_0 qua audio.cpp) — `LocalTTSEngine` mà `TTSManager.localEngine` trả khi
/// `tool == "vieneu"` và model hiệu lực là Turbo (`VieNeuModelChoice.current`).
///
/// ## Vì sao là facade riêng, không phải nhánh trong `VieNeuTTSService`
/// `VieNeuTTSService.shared` còn được gọi **thẳng** từ những chỗ chỉ dành cho Nano (nghe thử giọng Nano ở sheet chọn giọng,
/// nhân bản giọng Nano). Đặt công tắc model bên trong service Nano thì những chỗ đó âm thầm chạy Turbo khi trình đọc đang
/// chọn Turbo. Chọn ở `localEngine` (chỗ duy nhất đường đọc truyện lấy engine local) thì đường Nano không đổi một dòng.
///
/// ## Cùng hợp đồng với Nano
/// - Đi qua `PiperSynthesisCoordinator` ⇒ cùng 4 mức ưu tiên, gộp theo khoá, mỗi lúc một lượt tổng hợp.
/// - Trả `(data, pcmDuration, queueWaitMs, synthesisMs)` ⇒ `[NghiEnergy]` đo RTF như Nano.
/// - Chữ tới đây đã qua `TTSReplacementManager` ở tầng trên; ở đây chỉ chạy `VieNeuTurboTextFrontend` (số / ngày, tiếng
///   Nhật theo cờ VieNeu, phiên âm sea-g2p).
/// - **Không có tốc độ tổng hợp**: tham số `speed` bị bỏ qua (luôn 1×); tốc độ nghe do `NghiAudioPlayerQueue` lo.
///
/// ## Bộ nhớ
/// Dùng **chung** `VieNeuTurboRuntime.shared` / `VieNeuTurboTextFrontend.shared` với nghe thử giọng và nhân bản giọng
/// Turbo: một model 188 MB trong RAM, không phải hai. Runtime có thể bị nhả (trình đọc về Nano) ⇒ mỗi lượt tổng hợp đều
/// gọi `runtime.prepare` trước (đã nạp thì trả ngay). Engine Nano (ORT ~280 MB) bị nhả khi Turbo chuẩn bị và trước mỗi
/// lượt Turbo nếu ai đó đã nạp lại nó.
final class VieNeuTurboTTSService: LocalTTSEngine, @unchecked Sendable {
    static let shared: VieNeuTurboTTSService? = {
        guard let store = try? VieNeuTurboModelStore(), let frontend = VieNeuTurboTextFrontend.shared else { return nil }
        return VieNeuTurboTTSService(store: store, frontend: frontend)
    }()

    /// Cố định 2 luồng: iPhone chỉ có 2 lõi hiệu năng; đo 1.3.876 — 1 luồng RTF 2,17 (hụt tiếng), 2 luồng RTF 0,70.
    static let threadCount = 2
    /// Tần số của model (audio.cpp trả stereo 48 kHz, trộn về mono) — dùng cho đoạn im lặng tự sinh.
    static let sampleRate = 48_000
    /// QoS của lượt tổng hợp khi đọc truyện (1.3.885): `.userInitiated` được xếp lên **lõi hiệu năng**. Đo ở màn thử cũ
    /// (1.3.884, iPhone 11, 2 luồng, ~3 phút mỗi lượt): `.utility` (lõi tiết kiệm) RTF 0,71–0,73, CPU 1,35 CPU-s mỗi giây
    /// tiếng, tới phút thứ 2–3 máy "nóng"; `.userInitiated` RTF 0,35–0,36, CPU 0,70, máy chỉ "ấm" — lõi tiết kiệm phải
    /// chạy gấp đôi thời gian ở xung nhịp cao nên tốn điện hơn. (Trình đọc Nano không cần: ORT của nó vốn chạy ở mức
    /// của tác vụ gọi, đo trên máy đã nhanh như `.userInitiated`; runtime Turbo thì tự ép `.utility` nên phải truyền.)
    static let readerQoS: DispatchQoS.QoSClass = .userInitiated
    /// Tốc độ nghe mà Turbo còn tổng hợp kịp, để màn Cài đặt TTS cảnh báo khi vượt. Ở `readerQoS`: RTF trung bình ≈ 0,36,
    /// đoạn chậm nhất 0,41 (chỉ ~3 phút, máy "ấm") ⇒ 1 / 0,41 ≈ 2,4. Chừa khoảng cho máy nóng lên khi nghe lâu (ở
    /// `.utility` từng có đoạn vọt RTF 1,17 khi "nóng") và giọng chưa đo (Adam bựa) ⇒ 2,0, tức RTF phải dưới 0,5. Thanh
    /// tốc độ đi tới 5× nên cảnh báo vẫn hiện được. Trước 1.3.885 (`.utility`, RTF ≈ 0,70) mức này là 1,4.
    static let realtimeSpeedLimit = 2.0

    let store: VieNeuTurboModelStore
    let frontend: VieNeuTurboTextFrontend
    private let client: VieNeuTurboModelClient
    private let runtime = VieNeuTurboRuntime.shared
    private let voiceLock = NSLock()
    private var voiceDownloads: [String: Task<Void, Error>] = [:]

    init(store: VieNeuTurboModelStore, frontend: VieNeuTurboTextFrontend) {
        self.store = store
        self.frontend = frontend
        self.client = VieNeuTurboModelClient(store: store)
    }

    /// Đủ để đọc bằng Turbo: thư viện audio.cpp có trong bản build + model đúng dung lượng + manifest + `sea_g2p.bin`.
    /// File giọng từng giọng tải lúc cần. Gọi được ngoài `MainActor` (chỉ kiểm file).
    static var isReadyOnDisk: Bool {
        guard VieNeuTurboRuntime.isAvailable, let service = shared else { return false }
        return service.store.hasModel && service.store.hasManifest && service.frontend.hasDictionary
    }

    var engineStatus: String {
        "VieNeu-TTS v3 Turbo (GGUF q8_0, audio.cpp, 48 kHz, CPU \(Self.threadCount) luồng)"
    }

    // MARK: - Giọng

    /// Giọng mặc định của manifest (`minh_quan_pro` ở revision đang ghim).
    var defaultVoiceId: String {
        manifest()?.defaultVoice?.id ?? VieNeuTurboModelStore.fallbackVoiceId
    }

    /// Id có trong manifest thì giữ, không thì giọng mặc định — tên giọng Nano lọt sang (đổi model giữa chừng) không làm
    /// đoạn nào lỗi. Giọng **tự tạo** (`custom_…`, 1.3.892) giữ khi cặp file còn trên máy; đã xoá thì về mặc định.
    func resolveVoiceId(_ requested: String) -> String {
        if VieNeuTurboModelStore.isCustomVoiceId(requested), store.hasVoice(voiceId: requested) {
            return requested
        }
        guard let manifest = manifest() else {
            let usable = VieNeuTurboModelStore.isSafeVoiceId(requested) && !VieNeuTurboModelStore.isCustomVoiceId(requested)
            return usable ? requested : VieNeuTurboModelStore.fallbackVoiceId
        }
        if manifest.voices.contains(where: { $0.id == requested }) { return requested }
        return manifest.defaultVoice?.id ?? VieNeuTurboModelStore.fallbackVoiceId
    }

    /// Cặp file của giọng (vài KB) chưa có thì tải. Hai lượt cùng giọng (chọn ở Cài đặt + đoạn đầu tiên) dùng chung một
    /// lượt tải thay vì cùng ghi một file.
    func ensureVoice(_ voiceId: String) async throws {
        guard !store.hasVoice(voiceId: voiceId) else { return }
        let task = voiceDownloadTask(for: voiceId)
        defer { finishVoiceDownload(voiceId) }
        try await task.value
    }

    /// Tải trước file giọng vừa chọn ở Cài đặt — không chờ; lỗi thì đoạn đầu tiên tải lại.
    func prefetchVoice(_ voiceId: String) {
        let resolved = resolveVoiceId(voiceId)
        guard !store.hasVoice(voiceId: resolved) else { return }
        Task { [weak self] in
            do {
                try await self?.ensureVoice(resolved)
            } catch {
                AppLogger.shared.log("❌ [VieNeuTurbo] Tải giọng \(resolved) lỗi: \(error.localizedDescription)")
            }
        }
    }

    private func manifest() -> VieNeuTurboVoiceManifest? {
        guard store.hasManifest else { return nil }
        return try? VieNeuTurboVoiceManifest.load(from: store.manifestURL)
    }

    private func voiceDownloadTask(for voiceId: String) -> Task<Void, Error> {
        voiceLock.lock()
        defer { voiceLock.unlock() }
        if let existing = voiceDownloads[voiceId] { return existing }
        let client = self.client
        let created = Task { try await client.downloadVoice(voiceId: voiceId) }
        voiceDownloads[voiceId] = created
        return created
    }

    private func finishVoiceDownload(_ voiceId: String) {
        voiceLock.lock()
        voiceDownloads[voiceId] = nil
        voiceLock.unlock()
    }

    // MARK: - Chuẩn bị / nhả

    /// Nhả Nano rồi nạp model + dựng session 2 luồng + đủ file giọng. `TTSManager.scheduleNghiWarmUp` gọi khi chọn Turbo
    /// (và lúc mở app khi đang chọn Turbo) ⇒ đoạn đầu không phải chờ nạp model.
    func prepare(voice: String) async throws {
        await Self.releaseNanoEngineIfLoaded()
        let voiceId = resolveVoiceId(voice)
        try await ensureVoice(voiceId)
        let load = try await runtime.prepare(modelURL: store.modelURL, threads: Self.threadCount)
        let loadText = load.modelLoadMs.map { String(format: "nạp model %.0f ms", $0) } ?? "model đã nạp sẵn"
        AppLogger.shared.log(
            "🎙️ [VieNeuTurbo] Trình đọc sẵn sàng: giọng \(voiceId), \(Self.threadCount) luồng, \(loadText) — \(ProcessMemoryProbe.snapshot().summary)"
        )
    }

    /// Chuyển trình đọc về Nano: nhả model audio.cpp + bản đồ `sea_g2p.bin` của Turbo (`VieNeuTTSService.prepare` gọi).
    static func releaseForNano() async {
        await VieNeuTurboRuntime.shared.release()
        VieNeuTurboTextFrontend.shared?.unload()
    }

    /// Nhả engine Nano nếu đang nạp. Khoá của engine Nano có thể đang bị một lượt Nano giữ vài giây ⇒ chờ trên hàng đợi
    /// GCD, không chặn luồng của pool hợp tác.
    private static func releaseNanoEngineIfLoaded() async {
        guard let nano = VieNeuTTSService.shared else { return }
        let released = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: nano.releaseEngineRuntime())
            }
        }
        guard released else { return }
        AppLogger.shared.log("🎙️ [VieNeuTurbo] Đã nhả engine Nano để đọc bằng Turbo — \(ProcessMemoryProbe.snapshot().summary)")
    }

    // MARK: - Tổng hợp

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> Data {
        try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
        ).data
    }

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let effectiveKey = synthesisKey ?? Self.makeDefaultSynthesisKey(text: text, voice: voice, boundaryKind: boundaryKind)
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self else { throw CancellationError() }
            return try await self.executeInternalSynthesis(text: text, voice: voice, boundaryKind: boundaryKind)
        }
        return (
            data: payload.data,
            pcmDuration: payload.pcmDuration,
            queueWaitMs: payload.queueWaitMs,
            synthesisMs: payload.synthesisMs
        )
    }

    private func executeInternalSynthesis(
        text: String,
        voice: String,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        if PiperTTSService.isUnspeakable(text) { return Self.silencePayload(text: text) }
        await Self.releaseNanoEngineIfLoaded()
        let voiceId = resolveVoiceId(voice)
        try await ensureVoice(voiceId)
        _ = try await runtime.prepare(modelURL: store.modelURL, threads: Self.threadCount)

        let started = ProcessInfo.processInfo.systemUptime
        let cpuStarted = ProcessCPUClock.nowMs()
        let prepared = try await frontend.prepare(text)
        guard !prepared.phonemes.isEmpty else { return Self.silencePayload(text: text) }
        // audio.cpp không huỷ được giữa chừng ⇒ lượt đã bị bỏ thì dừng ở đây, đừng đốt vài giây CPU cho audio không ai nghe.
        try Task.checkCancellation()
        let output = try await runtime.synthesize(
            phonemes: prepared.phonemes,
            referenceCodesURL: store.referenceCodesURL(voiceId: voiceId),
            speakerEmbeddingURL: store.speakerEmbeddingURL(voiceId: voiceId),
            qos: Self.readerQoS
        )
        // Khoảng lặng đuôi theo ranh giới, như engine Nano chèn (tốc độ 1×) — thiếu nó các mảnh dính nhau nghe như mất chữ.
        var samples = output.samples
        let pause = VieNeuTTSEngine.pauseSeconds(for: boundaryKind)
        samples.append(contentsOf: [Float](repeating: 0, count: Int(Double(output.sampleRate) * pause)))
        let synthesisMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let pcmDuration = Double(samples.count) / Double(max(1, output.sampleRate))
        Self.logChunk(
            text: text, prepared: prepared, output: output, pause: pause, synthesisMs: synthesisMs,
            cpuMs: ProcessCPUClock.nowMs() - cpuStarted, boundaryKind: boundaryKind
        )
        return PiperSynthesisPayload(
            data: WAVEncoder.encodePCM16(samples: samples, sampleRate: output.sampleRate, channels: 1),
            pcmDuration: pcmDuration,
            synthesisMs: synthesisMs
        )
    }

    /// Một dòng mỗi đoạn: ms tổng hợp, giây tiếng (trừ khoảng lặng chèn thêm), RTF, CPU-s mỗi giây tiếng, QoS, nhiệt, RAM.
    private static func logChunk(
        text: String,
        prepared: VieNeuTurboTextFrontend.Prepared,
        output: VieNeuTurboRuntime.Output,
        pause: Double,
        synthesisMs: Double,
        cpuMs: Double,
        boundaryKind: TTSBoundaryKind
    ) {
        let speechSeconds = output.durationSeconds
        var fields: [String] = [
            "chars=\(text.count)",
            "phonemes=\(prepared.phonemes.count)",
            String(format: "frontendMs=%.0f", prepared.frontendMs),
            String(format: "runMs=%.0f", output.runMs),
            String(format: "synthMs=%.0f", synthesisMs),
            String(format: "audio=%.2fs", speechSeconds),
            String(format: "pause=%.2fs", pause),
            "RTF=\(ratio(synthesisMs / 1_000, speechSeconds))",
            "cpuPerAudio=\(ratio(cpuMs / 1_000, speechSeconds))",
            "boundary=\(boundaryKind.rawValue)",
            // QoS **đo được** của luồng tổng hợp — để biết khi khoá màn / chạy nền iOS có giữ lõi hiệu năng không.
            "qos=\(output.qosName)",
            "thermal=\(thermalName(ProcessInfo.processInfo.thermalState))"
        ]
        // Bộ đếm giờ của audio.cpp (1.3.924): tách nạp prompt / backbone / âm học / codec để so công tắc codec AMX.
        // CPU-time không đếm đủ phần chạy trên AMX ⇒ so bằng `codecMs` / RTF, đừng so `cpuPerAudio`.
        if let timings = output.timings {
            fields += [
                String(format: "prefillMs=%.0f", timings.prefillMs),
                String(format: "stepMs=%.0f", timings.stepMs),
                String(format: "acousticMs=%.0f", timings.acousticMs),
                String(format: "codecMs=%.0f", timings.codecMs),
                "gens=\(timings.generateCalls)"
            ]
        }
        fields.append("amx=\(codecAMXLabel(requested: output.codecAMXRequested, active: output.timings?.codecBLASActive))")
        AppLogger.shared.log(
            "🎙️ [VieNeuTurbo] Đoạn: " + fields.joined(separator: " ") + " — \(ProcessMemoryProbe.snapshot().summary)"
        )
    }

    /// "tắt" (công tắc tắt) · "bật" (codec chạy qua BLAS) · "lùi" (bật mà audio.cpp lùi về CPU) · "bật?" (không đo).
    private static func codecAMXLabel(requested: Bool, active: Bool?) -> String {
        guard requested else { return "tắt" }
        switch active {
        case true?: return "bật"
        case false?: return "lùi"
        case nil: return "bật?"
        }
    }

    /// "0.36"; mẫu ≈ 0 ⇒ "—".
    private static func ratio(_ numerator: Double, _ denominator: Double) -> String {
        guard denominator > 0.001 else { return "—" }
        return String(format: "%.2f", numerator / denominator)
    }

    /// Nhãn trạng thái nhiệt: tên của Apple (để khớp log của engine khác) + nghĩa tiếng Việt.
    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal: return "nominal (mát)"
        case .fair: return "fair (ấm)"
        case .serious: return "serious (nóng)"
        case .critical: return "critical (rất nóng)"
        @unknown default: return "unknown"
        }
    }

    private static func silencePayload(text: String) -> PiperSynthesisPayload {
        let spec = PiperTTSService.makeSilenceSpec(text: text, speed: 1.0, sampleRate: sampleRate)
        let data = WAVEncoder.encodePCM16(samples: spec.samples, sampleRate: spec.sampleRate, channels: 1)
        return PiperSynthesisPayload(data: data, pcmDuration: spec.pcmDuration)
    }

    /// Key mặc định khi caller bỏ trống — cùng khuôn `auto-<digest>` của Nano, có tiền tố `vieneu.turbo` ⇒ không bao giờ
    /// trùng khoá của Nano. Không có tốc độ: Turbo luôn 1×.
    private static func makeDefaultSynthesisKey(text: String, voice: String, boundaryKind: TTSBoundaryKind) -> String {
        let raw = "vieneu.turbo|\(voice)|\(boundaryKind.rawValue)|\(text)"
        var hash: UInt64 = 5381
        for byte in raw.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return "auto-\(String(hash, radix: 16))"
    }
}
