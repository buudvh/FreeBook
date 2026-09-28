import Foundation
import OnnxRuntimeBindings

/// Bộ thi hành **VieNeu-TTS v3 Nano** trên ONNX Runtime.
///
/// Pipeline (đối chiếu từng bước với `OnnxV3NanoEngine.infer` của bản tham chiếu, đã đọc nguyên văn):
///
/// ```text
/// phoneme (sea-g2p) ──> ids [1,L] ──┐
/// style [1,50,256] ─────────────────┴─> text_encoder ──> ctx [1,L,512]
///                                                          │
///                          duration_predictor(ctx, mask, spk) ──> log_s
///                                    secs = min(exp(log_s)/speed, 15)
///                                    T    = max(2, round(secs × 15.625))
///                          x = N(0,1)[1,144,T]
///                          lặp `steps` lần:  v = vector_estimator(x, t, ctx, mask, spk, style)
///                                            vu = vector_estimator(x, t, nullCtx, nullMask, nullSpk, nullStyle)
///                                            v  = vu + cfg × (v − vu)
///                                            x += (tg[i+1] − tg[i]) × v
///                          codec_decoder(x) ──> PCM float32 24 kHz
/// ```
///
/// Bốn điểm **cố ý bám sát bản tham chiếu** vì lệch một cái là hỏng tiếng:
/// 1. `t` truyền vào `vector_estimator` là `tg[i]` — thời gian **đã warp bởi `sway`**, không phải `u[i]`.
/// 2. Thứ tự warp: `tg = u + sway × (cos(π/2·u) − 1 + u)`, với `u = linspace(0, 1, steps+1)`.
/// 3. `x` khởi tạo bằng nhiễu **chuẩn tắc** (không phải đều) — flow matching huấn luyện với prior
///    Gaussian, đổi sang nhiễu đều là hỏng chất lượng mà không có lỗi nào báo.
/// 4. `T = max(2, round(secs × fps))` dùng `rounded(.toNearestOrEven)` cho khớp `round()` của Python
///    (làm tròn banker's), không dùng `.rounded()` mặc định của Swift.
///
/// `@unchecked Sendable` + một `NSLock` bọc trọn lượt tổng hợp: bốn `ORTSession` và `SeaG2P` đều không
/// an toàn đa luồng, và bản tham chiếu cũng bọc `infer` bằng `with self._lock`.
final class VieNeuTTSEngine: @unchecked Sendable {
    /// Một graph đã nạp kèm tên output đầu tiên — bản tham chiếu lấy `run(...)[0]`, tức **output theo
    /// thứ tự khai báo**, không theo tên.
    struct Graph {
        let session: ORTSession
        let outputName: String
    }

    struct Runtime {
        /// Giữ `ORTEnv` sống cùng các session. `ONNXPiperEngine` cũng lưu `env` trong `CachedRuntime`
        /// (`ONNXPiperEngine.swift:100-110`) — để nó là biến cục bộ của hàm nạp là mở đường cho một lỗi
        /// chỉ nổ sau khi hàm nạp trả về.
        let env: ORTEnv
        let textEncoder: Graph
        let durationPredictor: Graph
        let vectorEstimator: Graph
        let codecDecoder: Graph
    }

    struct FloatTensor {
        let shape: [NSNumber]
        let values: [Float]
    }

    struct Output {
        let data: Data
        /// PCM float32 đã cắt/fade. Giữ lại cùng `data` vì đường stream của tầng trên cần `[Float]` để
        /// dựng `TTSPCMChunkPayload` — giải mã ngược từ WAV chỉ để lấy lại đúng mảng này là việc vô nghĩa.
        let samples: [Float]
        let pcmDuration: Double
        let synthesisMs: Double
        let mode: VieNeuSynthesisPolicy.Mode
    }

    enum EngineError: LocalizedError {
        case modelMissing([String])
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .modelMissing(let names): return "Thiếu file model VieNeu-TTS: \(names.joined(separator: ", "))"
            case .badOutput(let name): return "Graph \(name) không trả về tensor mong đợi"
            }
        }
    }

    private let store: VieNeuModelStore
    private let lock = NSLock()

    private var runtime: Runtime?
    private var config: VieNeuConfig?
    private var catalog: VieNeuVoiceCatalog?
    private var phonemizer: SeaG2P?
    private var nullContext: FloatTensor?
    private var nullMask: [UInt8] = []
    var droppedScalarWarningShown = false

    var mode: VieNeuSynthesisPolicy.Mode = .high
    var consecutiveSlow = 0
    var consecutiveFast = 0

    init(store: VieNeuModelStore) {
        self.store = store
    }

    /// Chế độ đang dùng — `TTSManager` đọc để hiện trạng thái.
    var currentMode: VieNeuSynthesisPolicy.Mode {
        lock.lock(); defer { lock.unlock() }
        return mode
    }

    /// 24 kHz theo `config.json`; trước khi nạp xong thì trả về giá trị mặc định của model.
    var sampleRate: Int {
        lock.lock(); defer { lock.unlock() }
        return config?.sampleRate ?? 24_000
    }

    // MARK: - Nạp

    /// Nạp 4 session + config + catalog + phonemizer. Idempotent: gọi lại khi đã nạp thì trả về ngay.
    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
    }

    private func prepareLocked() throws {
        guard runtime == nil else { return }
        let missing = store.missingNames
        guard missing.isEmpty else { throw EngineError.modelMissing(missing) }

        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        try options.setIntraOpNumThreads(VieNeuSynthesisPolicy.threadCount)
        try options.setGraphOptimizationLevel(.all)

        func graph(_ name: String) throws -> Graph {
            let session = try ORTSession(
                env: env,
                modelPath: store.url(for: name).path,
                sessionOptions: options
            )
            guard let outputName = try session.outputNames().first else {
                throw EngineError.badOutput(name)
            }
            return Graph(session: session, outputName: outputName)
        }

        runtime = Runtime(
            env: env,
            textEncoder: try graph("text_encoder.onnx"),
            durationPredictor: try graph("duration_predictor.onnx"),
            vectorEstimator: try graph("vector_estimator.onnx"),
            codecDecoder: try graph("codec_decoder.onnx")
        )
        config = try VieNeuConfig.load(modelStore: store)
        catalog = try VieNeuVoiceCatalog.load(modelStore: store)
        phonemizer = try SeaG2P(binURL: store.url(for: "sea_g2p.bin"))
        try prepareNullBranchLocked()

        AppLogger.shared.log("🎙️ [VieNeu] Nạp xong engine: \(catalog?.presets.count ?? 0) giọng, threads=\(VieNeuSynthesisPolicy.threadCount)")
    }

    /// Nhánh **vô điều kiện** của CFG: chạy `text_encoder` với đúng `[bos, eos]` và `null_style`.
    /// Tính một lần cho cả vòng đời engine vì nó không phụ thuộc giọng đọc lẫn văn bản.
    private func prepareNullBranchLocked() throws {
        guard let runtime, let config else { throw EngineError.badOutput("config") }
        let nullStyle = FloatTensor(
            shape: [1, NSNumber(value: config.nStyle), NSNumber(value: config.styleDim)],
            values: config.constants.nullStyle
        )
        let ids: [Int64] = [config.bosID, config.eosID]
        var keepAlive: [NSMutableData] = []
        let idsValue = try int64Value(ids, shape: [1, 2], keepAlive: &keepAlive)
        let styleValue = try floatValue(nullStyle, keepAlive: &keepAlive)
        let outputs = try runtime.textEncoder.session.run(
            withInputs: ["ids": idsValue, "style": styleValue],
            outputNames: [runtime.textEncoder.outputName],
            runOptions: nil
        )
        guard let ctxValue = outputs[runtime.textEncoder.outputName] else {
            throw EngineError.badOutput("text_encoder (nhánh null)")
        }
        nullContext = FloatTensor(
            shape: [1, 2, NSNumber(value: config.dim)],
            values: try floats(from: ctxValue)
        )
        nullMask = [1, 1]
    }

    // MARK: - Tổng hợp

    /// Tổng hợp **một đoạn văn** thành WAV 24 kHz. `text` ở đây đã đi qua lớp thay thế ký tự dùng chung.
    func synthesize(text: String, voiceName: String, speed: Double) throws -> Output {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()

        guard let runtime, let config, let catalog, let phonemizer else {
            throw EngineError.badOutput("runtime")
        }
        guard let preset = catalog.preset(named: voiceName) ?? catalog.defaultPreset else {
            throw EngineError.badOutput("voices_v3_nano.json")
        }

        let tuning = VieNeuSynthesisPolicy.tuning(for: mode)
        let chunks = Self.splitIntoChunks(text, limit: VieNeuConfig.maxChunkCharacters)
        let started = ProcessInfo.processInfo.systemUptime

        var samples: [Float] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let phonemes = config.applyingEmotionTags(to: phonemizer.phonemizeTextWithEmotions(text: chunk))
            let encoded = config.encode(phonemes: phonemes)
            noteDroppedScalars(encoded.droppedScalars, total: encoded.ids.count)
            let chunkSamples = try runChunk(
                ids: encoded.ids,
                preset: preset,
                tuning: tuning,
                speed: speed,
                runtime: runtime,
                config: config
            )
            if index > 0 { samples.append(contentsOf: [Float](repeating: 0, count: Self.interChunkSilenceSamples(config.sampleRate))) }
            samples.append(contentsOf: chunkSamples)
        }

        let synthesisMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let pcmDuration = Double(samples.count) / Double(config.sampleRate)
        updateMode(synthesisMs: synthesisMs, pcmDuration: pcmDuration)

        return Output(
            data: WAVEncoder.encodePCM16(samples: samples, sampleRate: config.sampleRate, channels: 1),
            samples: samples,
            pcmDuration: pcmDuration,
            synthesisMs: synthesisMs,
            mode: mode
        )
    }

    /// Một chunk phoneme → PCM. Toàn bộ phần "dịch" số học của bản tham chiếu nằm ở đây.
    private func runChunk(
        ids: [Int64],
        preset: VieNeuVoiceCatalog.Preset,
        tuning: VieNeuSynthesisPolicy.Tuning,
        speed: Double,
        runtime: Runtime,
        config: VieNeuConfig
    ) throws -> [Float] {
        var keepAlive: [NSMutableData] = []

        let length = ids.count
        let idsValue = try int64Value(ids, shape: [1, NSNumber(value: length)], keepAlive: &keepAlive)
        let mask = ids.map { $0 == config.padID ? UInt8(0) : UInt8(1) }
        let maskValue = try boolValue(mask, shape: [1, NSNumber(value: length)], keepAlive: &keepAlive)
        let styleTensor = FloatTensor(
            shape: [1, NSNumber(value: config.nStyle), NSNumber(value: config.styleDim)],
            values: preset.style
        )
        let styleValue = try floatValue(styleTensor, keepAlive: &keepAlive)
        let speakerTensor = FloatTensor(
            shape: [1, NSNumber(value: preset.speakerEmbedding.count)],
            values: preset.speakerEmbedding
        )
        let speakerValue = try floatValue(speakerTensor, keepAlive: &keepAlive)

        // 1. text_encoder → ctx
        let textOutputs = try runtime.textEncoder.session.run(
            withInputs: ["ids": idsValue, "style": styleValue],
            outputNames: [runtime.textEncoder.outputName],
            runOptions: nil
        )
        guard let ctxValue = textOutputs[runtime.textEncoder.outputName] else {
            throw EngineError.badOutput("text_encoder")
        }
        let context = FloatTensor(
            shape: [1, NSNumber(value: length), NSNumber(value: config.dim)],
            values: try floats(from: ctxValue)
        )
        let contextValue = try floatValue(context, keepAlive: &keepAlive)

        // 2. duration_predictor → số giây
        let durationOutputs = try runtime.durationPredictor.session.run(
            withInputs: ["ctx": contextValue, "ctx_mask": maskValue, "spk": speakerValue],
            outputNames: [runtime.durationPredictor.outputName],
            runOptions: nil
        )
        guard let durationValue = durationOutputs[runtime.durationPredictor.outputName],
              let logSeconds = try floats(from: durationValue).first else {
            throw EngineError.badOutput("duration_predictor")
        }
        let seconds = min(exp(Double(logSeconds)) / max(speed, 1e-3), VieNeuConfig.maxChunkSeconds)
        let frames = max(VieNeuConfig.minFrames, Int((seconds * config.flowFPS).rounded(.toNearestOrEven)))

        // 3. Vòng Euler + CFG
        var latent = [Float](repeating: 0, count: config.latentChannels * frames)
        Self.fillStandardNormal(&latent)
        let steps = max(1, tuning.steps)
        let grid = Self.timeGrid(steps: steps, sway: tuning.sway)
        var timeValue = try floatValue(FloatTensor(shape: [1], values: [Float(grid[0])]), keepAlive: &keepAlive)
        let latentShape: [NSNumber] = [1, NSNumber(value: config.latentChannels), NSNumber(value: frames)]

        guard let nullContext else { throw EngineError.badOutput("nhánh null") }
        let nullContextValue = try floatValue(nullContext, keepAlive: &keepAlive)
        let nullMaskValue = try boolValue(nullMask, shape: [1, NSNumber(value: nullMask.count)], keepAlive: &keepAlive)
        let nullStyleValue = try floatValue(
            FloatTensor(
                shape: [1, NSNumber(value: config.nStyle), NSNumber(value: config.styleDim)],
                values: config.constants.nullStyle
            ),
            keepAlive: &keepAlive
        )
        let nullSpeakerValue = try floatValue(
            FloatTensor(
                shape: [1, NSNumber(value: config.constants.nullSpeaker.count)],
                values: config.constants.nullSpeaker
            ),
            keepAlive: &keepAlive
        )

        for step in 0..<steps {
            try Task.checkCancellation()
            let latentValue = try floatValue(FloatTensor(shape: latentShape, values: latent), keepAlive: &keepAlive)
            let conditioned = try velocity(
                runtime: runtime,
                x: latentValue,
                t: timeValue,
                ctx: contextValue,
                mask: maskValue,
                spk: speakerValue,
                style: styleValue
            )
            var velocityValues = conditioned
            if tuning.cfg > 0 {
                let unconditioned = try velocity(
                    runtime: runtime,
                    x: latentValue,
                    t: timeValue,
                    ctx: nullContextValue,
                    mask: nullMaskValue,
                    spk: nullSpeakerValue,
                    style: nullStyleValue
                )
                // v = vu + cfg × (v − vu)
                for index in velocityValues.indices {
                    velocityValues[index] = unconditioned[index]
                        + tuning.cfg * (velocityValues[index] - unconditioned[index])
                }
            }
            let delta = Float(grid[step + 1] - grid[step])
            for index in latent.indices {
                latent[index] += delta * velocityValues[index]
            }
            timeValue = try floatValue(FloatTensor(shape: [1], values: [Float(grid[step + 1])]), keepAlive: &keepAlive)
        }

        // 4. codec_decoder → PCM
        let latentFinal = try floatValue(FloatTensor(shape: latentShape, values: latent), keepAlive: &keepAlive)
        let decodeOutputs = try runtime.codecDecoder.session.run(
            withInputs: ["x": latentFinal],
            outputNames: [runtime.codecDecoder.outputName],
            runOptions: nil
        )
        guard let waveValue = decodeOutputs[runtime.codecDecoder.outputName] else {
            throw EngineError.badOutput("codec_decoder")
        }
        let waveform = try floats(from: waveValue)
        _ = keepAlive
        return Self.trimAndFade(waveform, sampleRate: config.sampleRate)
    }

}
