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

    let store: VieNeuModelStore
    let lock = NSLock()

    /// Bộ máy chính (ORT hoặc Core ML). Thay `runtime: VieNeuONNXRuntime?` (Phases 4–5) để hỗ trợ
    /// chuyển bộ máy tại runtime và rớt từng đoạn về ORT.
    private var backend: VieNeuInferenceBackend?
    /// Bộ máy fallback (luôn là ORT khi Core ML được chọn) — rớt từng đoạn khi Core ML lỗi (plan §2 Q2).
    private var fallbackRuntime: VieNeuONNXRuntime?
    private var config: VieNeuConfig?
    var catalog: VieNeuVoiceCatalog?
    private var phonemizer: SeaG2P?
    /// `ctx` của nhánh vô điều kiện (CFG) của **primary** — shape do bộ máy quyết định (ORT động / Core ML 200).
    /// Giữ **cả shape** vì shape đó do model quyết định, không suy được từ `config.json`.
    private var nullContext: [Float] = []
    private var nullContextShape: [Int64] = []
    private var nullMask: [UInt8] = []
    /// Null branch của **fallback ORT** — cần shape riêng (`L = 2`) nên không dùng được null branch của
    /// Core ML (vốn là `L = 200`). Chỉ có giá trị khi `fallbackRuntime != nil`.
    private var fallbackNullContext: [Float] = []
    private var fallbackNullContextShape: [Int64] = []
    private var fallbackNullMask: [UInt8] = []
    /// Toggle Core ML do người dùng chọn (đọc khi nạp engine). Mặc định `false` (plan §2 Q1).
    private var requestedCoreML = false

    // Trạng thái thích nghi — `+Adaptive` đọc/ghi, nên phải `internal` chứ không `private`.
    var droppedScalarWarningShown = false
    var mode: VieNeuSynthesisPolicy.Mode = .fast
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

    /// `true` khi bộ máy (ORT hoặc Core ML) đã nạp xong. Màn thử giọng dùng nó để biết lượt phát đầu tiên
    /// phải chờ nạp engine (~3 s đọc 4 graph + 62,8 MB `sea_g2p.bin`) hay không.
    var isPrepared: Bool {
        lock.lock(); defer { lock.unlock() }
        return backend != nil
    }

    /// Đổi yêu cầu bộ máy (toggle Core ML). Gọi từ tầng trên (`TTSManager`/`VieNeuTTSService`) để vô hiệu
    /// đệm backend — lượt `prepareLocked` kế tiếp dựng lại theo `requestedCoreML` mới. Giữ lock để không
    /// đua với `synthesize` đang giữ lock.
    func setRequestedCoreML(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        requestedCoreML = enabled
        backend = nil
        fallbackRuntime = nil
        nullContext = []
        nullContextShape = []
        nullMask = []
        fallbackNullContext = []
        fallbackNullContextShape = []
        fallbackNullMask = []
    }

    // MARK: - Nạp

    /// Nạp 4 session + config + catalog + phonemizer. Idempotent: gọi lại khi đã nạp thì trả về ngay.
    func prepare() throws {
        lock.lock()
        defer { lock.unlock() }
        try prepareLocked()
    }

    private func prepareLocked() throws {
        guard backend == nil else { return }
        let missing = store.missingNames
        // ONNX (`isReady`) là bắt buộc, **trừ khi** user đã tải riêng Core ML (`coreMLReady`): lúc đó Core ML
        // chạy một mình (không có ORT fallback). Xem `VieNeuBackendFactory.make`.
        guard missing.isEmpty || store.coreMLReady else { throw EngineError.modelMissing(missing) }

        // Dựng **hết** vào biến cục bộ rồi mới gán (xem doc cũ). `nullContext`/`nullMask`/`nullSpeaker`/
        // `nullStyle` là **bất biến suốt vòng đời engine** (chỉ gán đúng một lần ở đây; engine không có
        // `unload`) ⇒ tensor cache của A2b an toàn. Factory luôn dựng ORT làm fallback khi Core ML bật.
        let newConfig = try VieNeuConfig.load(modelStore: store)
        let newCatalog = try VieNeuVoiceCatalog.load(modelStore: store)
        let newPhonemizer = try SeaG2P(binURL: store.url(for: "sea_g2p.bin"))
        let choice = try VieNeuBackendFactory.make(
            store: store, config: newConfig, useCoreML: requestedCoreML,
            threadCount: VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard)
        )
        let newBackend = choice.primary
        let newFallback = choice.fallback

        let nullBranch = try Self.makeNullBranch(backend: newBackend, config: newConfig)
        // Null branch riêng cho fallback ORT (shape `L = 2`, khác null branch Core ML `L = 200`).
        var fallbackNull: (context: [Float], shape: [Int64], mask: [UInt8])? = nil
        if let fallback = newFallback {
            fallbackNull = try Self.makeNullBranch(backend: fallback, config: newConfig)
        }

        backend = newBackend
        fallbackRuntime = newFallback
        config = newConfig
        catalog = newCatalog
        phonemizer = newPhonemizer
        nullContext = nullBranch.context
        nullContextShape = nullBranch.shape
        nullMask = nullBranch.mask
        fallbackNullContext = fallbackNull?.context ?? []
        fallbackNullContextShape = fallbackNull?.shape ?? []
        fallbackNullMask = fallbackNull?.mask ?? []

        AppLogger.shared.log("🎙️ [VieNeu] Nạp xong engine: \(newCatalog.presets.count) giọng, backend=\(newBackend.backendID), threads=\(VieNeuSynthesisPolicy.effectiveThreadCount(from: .standard))")
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

        guard let backend, let config, let catalog, let phonemizer else {
            throw EngineError.notPrepared
        }
        guard let preset = catalog.preset(named: voiceName) ?? catalog.defaultPreset else {
            throw EngineError.badOutput("voices_v3_nano.json")
        }

        let activeMode = VieNeuSynthesisPolicy.effectiveMode(requested: requestedMode, current: mode)
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
        // Bộ đếm churn tính từ đầu lượt này (không tích luỹ qua các lượt) để con số ứng đúng đoạn đang đọc.
        backend.resetChurnCounters()

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
            logChunkPhonemes(index: index, text: chunk.text, phonemes: phonemes)
            let encoded = config.encode(phonemes: phonemes)
            droppedScalars += encoded.droppedScalars
            noteDroppedScalars(encoded.droppedScalars, total: encoded.ids.count)
            if index > 0 { gaps.append(chunks[index - 1].gap) }
            waveforms.append(try runChunk(
                ids: encoded.ids,
                preset: preset,
                tuning: tuning,
                speed: speed,
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
            boundaryKind: boundaryKind, timing: timing, synthesisSpeed: speed
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

    /// Một chunk phoneme → PCM. Toàn bộ đường ống 4 bước nằm ở `vieNeuOrchestrateChunk`
    /// (dùng chung ORT lẫn Core ML). Ở đây chỉ **uỷ quyền** cho bộ máy chính và **bọc try/catch** để
    /// rớt từng đoạn về ORT khi Core ML ném (plan §2 Q2) — không khựng, không im lặng toàn chương.
    private func runChunk(
        ids: [Int64],
        preset: VieNeuVoiceCatalog.Preset,
        tuning: VieNeuSynthesisPolicy.Tuning,
        speed: Double,
        config: VieNeuConfig,
        timing: inout Timing
    ) throws -> [Float] {
        guard let backend else { throw EngineError.notPrepared }
        do {
            return try backend.runChunk(
                ids: ids, preset: preset, tuning: tuning, speed: speed, config: config,
                nullContext: nullContext, nullContextShape: nullContextShape, nullMask: nullMask,
                timing: &timing
            )
        } catch {
            guard let fallback = fallbackRuntime else { throw error }
            AppLogger.shared.log("⚠️ [VieNeuFallback] Core ML lỗi chunk: \(error.localizedDescription) — rớt về ORT.")
            return try fallback.runChunk(
                ids: ids, preset: preset, tuning: tuning, speed: speed, config: config,
                nullContext: fallbackNullContext, nullContextShape: fallbackNullContextShape,
                nullMask: fallbackNullMask, timing: &timing
            )
        }
    }
}
