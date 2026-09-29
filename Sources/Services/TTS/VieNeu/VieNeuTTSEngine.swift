import Foundation

/// Bộ thi hành **VieNeu-TTS v3 Nano**.
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
///                          lặp `steps` lần:  v  = vector_estimator(x, t, ctx, mask, spk, style)
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
/// Tầng ONNX nằm ở `VieNeuONNXRuntime` — **C API**, không phải lớp ObjC. Lý do ở doc của file đó:
/// `ctx_mask` là tensor bool, mà `ORTTensorElementDataType` của wrapper ObjC không có case `Bool` ở
/// **mọi** bản phát hành còn dùng được.
///
/// `@unchecked Sendable` + một `NSLock` bọc trọn lượt tổng hợp: bốn `OrtSession` và `SeaG2P` đều không
/// an toàn đa luồng, và bản tham chiếu cũng bọc `infer` bằng `with self._lock`.
final class VieNeuTTSEngine: @unchecked Sendable {
    struct Output {
        let data: Data
        /// PCM float32 đã cắt/fade. Giữ lại cùng `data` vì đường stream của tầng trên cần `[Float]` để
        /// dựng `TTSPCMChunkPayload` — giải mã ngược từ WAV chỉ để lấy lại đúng mảng này là việc vô nghĩa.
        let samples: [Float]
        let pcmDuration: Double
        let synthesisMs: Double
        let mode: VieNeuSynthesisPolicy.Mode
        /// Số phoneme bị bỏ vì không có trong vocab.
        ///
        /// Khác 0 nghĩa là text đầu vào sinh ra ký tự mà model không đọc được. Đây đúng loại lỗi đã làm
        /// audio ra "không phải tiếng Việt" mà mọi thứ khác vẫn đúng, nên nó phải **hiện ra ở màn thử
        /// giọng**, không chỉ nằm trong log (log chỉ ghi khi người dùng bật `AppLogger`).
        let droppedScalars: Int
        /// Số chunk văn bản đã tách. Có mặt vì đúng lỗi vừa rồi (từ bị chẻ đôi ở ranh giới chunk) sẽ hiện
        /// ra ngay nếu biết số chunk — người dùng thấy "chunk: 3" cho một câu mà lẽ ra chỉ 2 là biết ngay.
        let chunkCount: Int
        /// Độ dài audio **trừ** các khoảng nghỉ do engine tự chèn. RTF tính trên tổng độ dài bị **thổi
        /// phồng** bởi khoảng nghỉ (chúng không tốn thời gian suy luận), nên cần con số này để đọc đúng
        /// hiệu năng thật.
        let speechDuration: Double
        /// Thời gian tách theo nhóm việc — xem doc của `Timing`.
        let timing: Timing
        /// Phoneme của chunk đầu (cắt ngắn). Đây là **bằng chứng duy nhất** phân biệt được hai nguyên nhân
        /// hay gặp của "đọc sai": từ điển trả phoneme sai, hay phoneme đúng mà model đọc bằng giọng Việt.
        let phonemeSample: String
    }

    enum EngineError: LocalizedError {
        case modelMissing([String])
        case notPrepared
        case badOutput(String)

        var errorDescription: String? {
            switch self {
            case .modelMissing(let names):
                return "Thiếu file model VieNeu-TTS: \(names.joined(separator: ", "))"
            case .notPrepared:
                // Không nêu tên graph: thiếu cái nào cũng là "chưa nạp xong", và nói sai chỗ từng làm
                // người dùng đi tìm lỗi ở tầng ONNX trong khi nguyên nhân nằm ở bước nạp.
                return "Engine VieNeu chưa nạp xong. Thử lại; nếu vẫn lỗi thì model tải về chưa đủ."
            case .badOutput(let name):
                return "Graph \(name) không trả về tensor mong đợi"
            }
        }
    }

    private let store: VieNeuModelStore
    private let lock = NSLock()

    private var runtime: VieNeuONNXRuntime?
    private var config: VieNeuConfig?
    private var catalog: VieNeuVoiceCatalog?
    private var phonemizer: SeaG2P?
    /// `ctx` của nhánh vô điều kiện (CFG) — không phụ thuộc giọng lẫn văn bản nên tính một lần.
    /// Giữ **cả shape** vì shape đó do model quyết định, không suy được từ `config.json`.
    private var nullContext: [Float] = []
    private var nullContextShape: [Int64] = []
    private var nullMask: [UInt8] = []

    // Trạng thái thích nghi — `+Adaptive` đọc/ghi, nên phải `internal` chứ không `private`.
    var droppedScalarWarningShown = false
    var mode: VieNeuSynthesisPolicy.Mode = .high
    /// Chế độ **người dùng chọn**. `nil` = tự thích nghi theo RTF (mặc định).
    ///
    /// Khi có giá trị, `updateMode` bị bỏ qua hoàn toàn — nếu không, bộ thích nghi sẽ tự nâng/hạ và ghi
    /// đè đúng cái người dùng vừa chọn, làm ô chọn trong UI nói một đằng máy chạy một nẻo.
    private var requestedMode: VieNeuSynthesisPolicy.Mode?
    var consecutiveSlow = 0
    var consecutiveFast = 0

    init(store: VieNeuModelStore) {
        self.store = store
    }

    /// Chế độ đang **thực sự** chạy (đã tính cả lựa chọn của người dùng).
    var currentMode: VieNeuSynthesisPolicy.Mode {
        lock.lock(); defer { lock.unlock() }
        return requestedMode ?? mode
    }

    /// Đặt chế độ cố định. Truyền `nil` để quay lại tự thích nghi theo RTF.
    func setRequestedMode(_ requested: VieNeuSynthesisPolicy.Mode?) {
        lock.lock(); defer { lock.unlock() }
        requestedMode = requested
        if let requested { mode = requested }
        consecutiveSlow = 0
        consecutiveFast = 0
    }

    /// 24 kHz theo `config.json`; trước khi nạp xong thì trả về giá trị mặc định của model.
    var sampleRate: Int {
        lock.lock(); defer { lock.unlock() }
        return config?.sampleRate ?? 24_000
    }

    /// `true` khi 4 session ONNX đã nạp xong. Màn thử giọng dùng nó để biết lượt phát đầu tiên phải chờ
    /// nạp engine (~3 s đọc 4 graph + 62,8 MB `sea_g2p.bin`) hay không.
    var isPrepared: Bool {
        lock.lock(); defer { lock.unlock() }
        return runtime != nil
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

        // Dựng **hết** vào biến cục bộ rồi mới gán. Gán từng cái như bản đầu là mở đường cho trạng thái
        // nửa vời: `runtime` đã có mà `config` chưa ⇒ `isPrepared` nói dối, mọi lượt sau nhảy qua bước
        // nạp, và lỗi thật bị che bởi một guard ở tầng dưới ("Graph runtime…"). Đúng chuyện đã xảy ra
        // khi `NPZReader` còn đọc sai kích thước entry.
        let newRuntime = try VieNeuONNXRuntime(modelStore: store, threadCount: VieNeuSynthesisPolicy.threadCount)
        let newConfig = try VieNeuConfig.load(modelStore: store)
        let newCatalog = try VieNeuVoiceCatalog.load(modelStore: store)
        let newPhonemizer = try SeaG2P(binURL: store.url(for: "sea_g2p.bin"))
        let nullBranch = try Self.makeNullBranch(runtime: newRuntime, config: newConfig)

        runtime = newRuntime
        config = newConfig
        catalog = newCatalog
        phonemizer = newPhonemizer
        nullContext = nullBranch.context
        nullContextShape = nullBranch.shape
        nullMask = nullBranch.mask

        AppLogger.shared.log("🎙️ [VieNeu] Nạp xong engine: \(newCatalog.presets.count) giọng, threads=\(VieNeuSynthesisPolicy.threadCount)")
    }

    /// Nhánh **vô điều kiện** của CFG: chạy `text_encoder` với đúng `[bos, eos]` và `null_style`.
    ///
    /// Là hàm `static` nhận tham số (thay vì method đọc trạng thái của `self`) để `prepareLocked` chỉ
    /// phải gán trạng thái **sau khi** biết chắc mọi bước đều đã thành công.
    private static func makeNullBranch(
        runtime: VieNeuONNXRuntime,
        config: VieNeuConfig
    ) throws -> (context: [Float], shape: [Int64], mask: [UInt8]) {
        let context = try runtime.textEncoder(
            ids: [config.bosID, config.eosID],
            style: config.constants.nullStyle,
            styleRows: config.nStyle,
            styleColumns: config.styleDim
        )
        return (context.values, context.shape, [1, 1])
    }

    // MARK: - Tổng hợp

    /// Tổng hợp **một đoạn văn** thành WAV 24 kHz. `text` tới đây đã qua `applyReplacements` (thay thế
    /// ký tự chung, mọi engine) và `normalizeVietnameseText` (mở rộng số/ngày, không espeak) — đều ở
    /// tầng trên — nên engine chỉ tách chunk và tổng hợp, **không** tự tiền xử lý.
    func synthesize(
        text: String,
        voiceName: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd
    ) throws -> Output {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()

        guard let runtime, let config, let catalog, let phonemizer else {
            throw EngineError.notPrepared
        }
        guard let preset = catalog.preset(named: voiceName) ?? catalog.defaultPreset else {
            throw EngineError.badOutput("voices_v3_nano.json")
        }

        let activeMode = requestedMode ?? mode
        let tuning = VieNeuSynthesisPolicy.tuning(for: activeMode)
        // Văn bản tới đây đã đi qua **hai** lớp tiền xử lý ở tầng trên:
        // 1. `TTSReplacementManager.applyReplacements` (thay thế ký tự chung, mọi engine) — tại
        //    `TTSManager.speakCurrent` / `scheduleNghiRefill`.
        // 2. `TextPreprocessor.normalizeVietnameseText` (mở rộng số/ngày, không espeak) — tại
        //    `VieNeuTTSService.executeInternalSynthesis` / `…Stream`. `sea_g2p.bin` không có chữ số nên
        //    bước này bắt buộc, nếu không `8/1999` bị nuốt 10 ký tự.
        // Engine KHÔNG tự tiền xử lý — nhận văn bản đã sẵn sàng để tách chunk.
        let chunks = Self.splitIntoChunks(
            text,
            limit: VieNeuConfig.maxChunkCharacters
        )
        let started = ProcessInfo.processInfo.systemUptime

        var waveforms: [[Float]] = []
        var gaps: [Chunk.Gap] = []
        var droppedScalars = 0
        var timing = Timing()
        var phonemeLines: [String] = []
        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let phonemes = config.applyingEmotionTags(to: phonemizer.phonemizeTextWithEmotions(text: chunk.text))
            // **Mỗi chunk một dòng**: in phoneme của cả đoạn chứ không chỉ chunk đầu. Bản trước chỉ in
            // chunk 0 nên người dùng không soi được chunk nào đọc sai — mà đó mới là thứ cần thấy.
            phonemeLines.append("[\(index)] \(phonemes)")
            let encoded = config.encode(phonemes: phonemes)
            droppedScalars += encoded.droppedScalars
            noteDroppedScalars(encoded.droppedScalars, total: encoded.ids.count)
            if index > 0 { gaps.append(chunks[index - 1].gap) }
            waveforms.append(try runChunk(
                ids: encoded.ids,
                preset: preset,
                tuning: tuning,
                speed: speed,
                runtime: runtime,
                config: config,
                timing: &timing
            ))
        }

        // Ghép chunk **sau** khi đã có đủ waveform: khớp âm lượng cần biết mức của tất cả các chunk.
        let joined = Self.joinChunks(waveforms, gaps: gaps, sampleRate: config.sampleRate)
        // Khoảng lặng **đuôi** theo ranh giới. `joinChunks` không bao giờ chèn cho chunk cuối, mà tầng trên
        // (Reader) cắt một đoạn văn thành nhiều utterance — mỗi utterance là một payload riêng đã bị
        // `trimAndFade` cắt còn ~40 ms đệm. Thiếu khoảng lặng này thì utterance kế tiếp dính liền và người
        // dùng nghe như **mất chữ**. Chia cho `speed` cho khớp `ONNXPiperEngine`.
        let boundarySilenceSeconds = Self.pauseSeconds(for: boundaryKind) / max(0.1, speed)
        var samples = joined.samples
        if boundarySilenceSeconds > 0 {
            samples.append(contentsOf: [Float](
                repeating: 0,
                count: Int(Double(config.sampleRate) * boundarySilenceSeconds)
            ))
        }
        // Khoảng lặng chèn thêm **không phải** lời đọc ⇒ phải cộng vào `insertedPauseSeconds`, nếu không
        // `speechDuration` (dùng để tính RTF theo lời nói) sẽ bị thổi lên.
        let insertedPauseSeconds = joined.pauseSeconds + boundarySilenceSeconds

        let synthesisMs = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        let pcmDuration = Double(samples.count) / Double(config.sampleRate)
        // Số liệu **mỗi lượt tổng hợp** — xem doc của `logSynthesisPerf` ở `+Adaptive`.
        logSynthesisPerf(
            mode: activeMode, chunkCount: chunks.count, droppedScalars: droppedScalars,
            characterCount: text.count, pcmDuration: pcmDuration,
            speechDuration: max(0, pcmDuration - insertedPauseSeconds), synthesisMs: synthesisMs,
            boundaryKind: boundaryKind
        )
        // Chỉ thích nghi khi người dùng để "tự động"; xem doc của `requestedMode`.
        if requestedMode == nil {
            updateMode(synthesisMs: synthesisMs, pcmDuration: pcmDuration)
        }

        return Output(
            data: WAVEncoder.encodePCM16(samples: samples, sampleRate: config.sampleRate, channels: 1),
            samples: samples,
            pcmDuration: pcmDuration,
            synthesisMs: synthesisMs,
            mode: activeMode,
            droppedScalars: droppedScalars,
            chunkCount: chunks.count,
            speechDuration: max(0, pcmDuration - insertedPauseSeconds),
            timing: timing,
            phonemeSample: phonemeLines.joined(separator: "\n")
        )
    }

    /// Một chunk phoneme → PCM. Toàn bộ phần "dịch" số học của bản tham chiếu nằm ở đây.
    private func runChunk(
        ids: [Int64],
        preset: VieNeuVoiceCatalog.Preset,
        tuning: VieNeuSynthesisPolicy.Tuning,
        speed: Double,
        runtime: VieNeuONNXRuntime,
        config: VieNeuConfig,
        timing: inout Timing
    ) throws -> [Float] {
        // Số token không cần biến riêng: `mask` lấy từ `ids`, còn shape của `ctx` đọc từ model.
        let mask = ids.map { $0 == config.padID ? UInt8(0) : UInt8(1) }

        let chunkStarted = ProcessInfo.processInfo.systemUptime

        // 1. text_encoder → ctx, kèm **shape thật** để hai bước sau dùng lại
        let context = try runtime.textEncoder(
            ids: ids,
            style: preset.style,
            styleRows: config.nStyle,
            styleColumns: config.styleDim
        )

        // 2. duration_predictor → số giây
        let logSeconds = try runtime.durationPredictor(
            context: context.values,
            contextShape: context.shape,
            mask: mask,
            speaker: preset.speakerEmbedding
        )
        let seconds = min(exp(Double(logSeconds)) / max(speed, 1e-3), VieNeuConfig.maxChunkSeconds)
        let frames = max(VieNeuConfig.minFrames, Int((seconds * config.flowFPS).rounded(.toNearestOrEven)))

        // 3. Vòng Euler + CFG
        var latent = [Float](repeating: 0, count: config.latentChannels * frames)
        Self.fillStandardNormal(&latent)
        let steps = max(1, tuning.steps)
        let grid = Self.timeGrid(steps: steps, sway: tuning.sway)

        let vectorStarted = ProcessInfo.processInfo.systemUptime

        for step in 0..<steps {
            try Task.checkCancellation()
            let conditioned = try runtime.vectorEstimator(
                latent: latent,
                time: Float(grid[step]),
                context: context.values,
                contextShape: context.shape,
                mask: mask,
                speaker: preset.speakerEmbedding,
                style: preset.style,
                styleRows: config.nStyle,
                styleColumns: config.styleDim,
                latentChannels: config.latentChannels,
                frames: frames
            )
            var velocity = conditioned
            if tuning.cfg > 0 {
                let unconditioned = try runtime.vectorEstimator(
                    latent: latent,
                    time: Float(grid[step]),
                    context: nullContext,
                    contextShape: nullContextShape,
                    mask: nullMask,
                    speaker: config.constants.nullSpeaker,
                    style: config.constants.nullStyle,
                    styleRows: config.nStyle,
                    styleColumns: config.styleDim,
                    latentChannels: config.latentChannels,
                    frames: frames
                )
                // v = vu + cfg × (v − vu)
                for index in velocity.indices {
                    velocity[index] = unconditioned[index]
                        + tuning.cfg * (velocity[index] - unconditioned[index])
                }
            }
            let delta = Float(grid[step + 1] - grid[step])
            for index in latent.indices {
                latent[index] += delta * velocity[index]
            }
        }

        // 4. codec_decoder → PCM
        let waveform = try runtime.codecDecoder(
            latent: latent,
            latentChannels: config.latentChannels,
            frames: frames
        )
        // `otherMs` = phần còn lại của chunk. Đo bằng `chunkMs - vectorMs` chứ **không** đo riêng phần
        // text_encoder/codec rồi cộng: đo cả chunk mà không trừ là đếm phần vector hai lần.
        let vectorMs = (ProcessInfo.processInfo.systemUptime - vectorStarted) * 1_000
        let chunkMs = (ProcessInfo.processInfo.systemUptime - chunkStarted) * 1_000
        timing.vectorMs += vectorMs
        timing.otherMs += max(0, chunkMs - vectorMs)

        return Self.trimAndFade(waveform, sampleRate: config.sampleRate)
    }
}
