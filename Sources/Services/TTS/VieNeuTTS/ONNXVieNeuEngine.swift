import Foundation
import OnnxRuntimeBindings

/// Engine tổng hợp VieNeu-TTS v3 Turbo trên ONNX Runtime.
///
/// Bốn session, tất cả chạy CPU:
/// `vieneu_prefill` · `vieneu_decode_step` · `vieneu_acoustic_cached` · `moss_audio_tokenizer_decode_full`.
///
/// **Không dùng CoreML EP.** KV cache của graph này có chiều 0 ở bước đầu và CoreML không nhận
/// chiều 0; thử nghiệm trước đã phải bỏ CoreML sau khi nó crash trên đúng chỗ đó. Cũng không dùng
/// XNNPACK: các graph này có shape KV động nên XNNPACK phân vùng kém rồi rơi về CPU.
///
/// **4 luồng là mặc định có căn cứ, không phải bỏ sót.** Bước decode phải đọc toàn bộ weight của
/// backbone mỗi frame; số đo trên iPhone 11 cho 20.8 GB/s với 4 luồng, tức gần trần băng thông của
/// A13. Hạ về 1 luồng như đường Piper sẽ **chậm hơn** — Piper dùng 1 luồng vì mô hình của nó nhỏ và
/// vì điện năng, không vì tốc độ.
final class ONNXVieNeuEngine: @unchecked Sendable {
    /// Số luồng intra-op. Đổi được qua UserDefaults để đo lại trên máy thật mà không phải build lại.
    static let intraOpThreadsKey = "vieneuIntraOpThreads"

    /// Nội bộ (không `private`) để `ONNXVieNeuEngine+SelfCheck` dùng được.
    struct Runtime {
        let modelDirectory: URL
        let environment: ORTEnv
        let prefillSession: ORTSession
        let decodeSession: ORTSession
        let acousticSession: ORTSession
        let codecSession: ORTSession
        let codecOutputNames: Set<String>
        let config: VieNeuModelConfig
        let tables: VieNeuEmbeddingTables
        let tokenizer: VieNeuTokenizer
        let g2p: SeaG2P
        let catalog: VieNeuVoiceCatalog
        let decodeLoop: VieNeuDecodeLoop
    }

    private let store: VieNeuModelStore
    var runtime: Runtime?
    private let runtimeLock = NSLock()
    /// Anchor đã tính cho từng giọng — phép chiếu x-vector không đổi theo chunk nên chỉ tính một lần.
    private var anchorCache: [String: [Float]] = [:]
    /// Đã chạy tự kiểm cho runtime hiện tại chưa.
    private var didRunSelfCheck = false

    init(store: VieNeuModelStore) {
        self.store = store
    }

    var voices: [VieNeuVoice] {
        (try? loadRuntime())?.catalog.voices ?? []
    }

    var defaultVoiceName: String? {
        (try? loadRuntime())?.catalog.defaultVoiceName
    }

    /// Nạp trước toàn bộ session, bảng embedding và từ điển.
    func prepare() throws {
        selfCheckIfNeeded(runtime: try loadRuntime())
    }

    /// Chạy tự kiểm **sau khi `runtimeLock` đã nhả**.
    ///
    /// Không gọi từ trong `loadRuntime()`: `runSelfCheck` đi qua `resolveAnchor`, mà hàm đó cũng lấy
    /// `runtimeLock` — `NSLock` không phải khoá đệ quy nên gọi lồng là treo cứng ngay lần nạp đầu.
    func selfCheckIfNeeded(runtime: Runtime) {
        runtimeLock.lock()
        let shouldRun = !didRunSelfCheck
        didRunSelfCheck = true
        runtimeLock.unlock()
        guard shouldRun else { return }
        runSelfCheck(runtime: runtime)
    }

    // MARK: - Nạp runtime

    func loadRuntime() throws -> Runtime {
        runtimeLock.lock()
        defer { runtimeLock.unlock() }

        let directory = store.modelDirectoryURL
        if let runtime, runtime.modelDirectory == directory { return runtime }

        let missing = store.missingFiles()
        guard missing.isEmpty else {
            throw TTSError.modelNotCached(
                "Bộ model VieNeu chưa tải đủ, còn thiếu: \(missing.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let start = CFAbsoluteTimeGetCurrent()
        let environment = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        let threads = Self.resolveThreadCount()
        try options.setIntraOpNumThreads(Int32(threads))
        try options.setGraphOptimizationLevel(.all)
        // Threadpool của ORT spin-wait giữa các lần run. Với ~212 lần run cho mỗi giây audio thì
        // phần spin đốt điện liên tục mà không đổi lấy tốc độ.
        try? options.addConfigEntry(withKey: "session.intra_op.allow_spinning", value: "0")

        let prefillSession = try ORTSession(
            env: environment,
            modelPath: store.url(for: .prefill).path,
            sessionOptions: options
        )
        let decodeSession = try ORTSession(
            env: environment,
            modelPath: store.url(for: .decodeStep).path,
            sessionOptions: options
        )
        let acousticSession = try ORTSession(
            env: environment,
            modelPath: store.url(for: .acoustic).path,
            sessionOptions: options
        )
        let codecSession = try ORTSession(
            env: environment,
            modelPath: store.url(for: .codecDecode).path,
            sessionOptions: options
        )

        let config = try VieNeuModelConfig(url: store.url(for: .config))
        let prefillLayout = try VieNeuSessionLayout(session: prefillSession, label: "prefill")
        let decodeLayout = try VieNeuSessionLayout(session: decodeSession, label: "decode_step")
        let acousticLayout = try VieNeuSessionLayout(session: acousticSession, label: "acoustic")

        guard decodeLayout.layerCount == config.numHiddenLayers else {
            throw TTSError.internalError(
                "decode_step có \(decodeLayout.layerCount) layer nhưng config khai \(config.numHiddenLayers)"
            )
        }

        let tables = try VieNeuEmbeddingTables(npzURL: store.url(for: .heads), config: config)
        if config.usesSpeakerEmbedding && !tables.canBuildSpeakerAnchor {
            throw TTSError.internalError("Bộ model cần speaker embedding nhưng npz thiếu xvec_* — bộ model và npz lệch nhau")
        }

        let runtime = Runtime(
            modelDirectory: directory,
            environment: environment,
            prefillSession: prefillSession,
            decodeSession: decodeSession,
            acousticSession: acousticSession,
            codecSession: codecSession,
            codecOutputNames: Set(try codecSession.outputNames()),
            config: config,
            tables: tables,
            tokenizer: try VieNeuTokenizer(jsonURL: store.url(for: .tokenizer)),
            g2p: try SeaG2P(dictionaryURL: store.url(for: .seaG2P)),
            catalog: try VieNeuVoiceCatalog(jsonURL: store.url(for: .voices)),
            decodeLoop: VieNeuDecodeLoop(
                prefillSession: prefillSession,
                decodeSession: decodeSession,
                acousticSession: acousticSession,
                prefillLayout: prefillLayout,
                decodeLayout: decodeLayout,
                acousticLayout: acousticLayout,
                tables: tables,
                config: config
            )
        )
        self.runtime = runtime
        self.anchorCache.removeAll()
        self.didRunSelfCheck = false

        AppLogger.shared.log(
            """
            🗣️ [VieNeu] Nạp runtime \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start))s \
            threads=\(threads) layers=\(decodeLayout.layerCount) localLayers=\(acousticLayout.layerCount) \
            nVQ=\(config.codebookCount) voices=\(runtime.catalog.voices.count) \
            speakerEmb=\(config.usesSpeakerEmbedding) sr=\(config.audioSampleRate)
            """
        )
        return runtime
    }

    private static func resolveThreadCount() -> Int {
        let stored = UserDefaults.standard.integer(forKey: intraOpThreadsKey)
        guard stored > 0 else { return 4 }
        return min(max(1, stored), ProcessInfo.processInfo.processorCount)
    }

    // MARK: - Tổng hợp

    /// Tổng hợp một chunk thành WAV mono.
    ///
    /// `text` phải **đã đi qua** `TextPreprocessor` với profile `.vieneu`: bộ ký hiệu phoneme của
    /// sea-g2p dùng chữ số làm dấu thanh (`aː2`, `a6j`), nên một chữ số thô còn lại trong text sẽ
    /// bị model đọc thành thanh điệu.
    func synthesize(
        text: String,
        voiceName: String,
        boundaryKind: TTSBoundaryKind
    ) throws -> (data: Data, pcmDuration: Double) {
        let runtime = try loadRuntime()
        selfCheckIfNeeded(runtime: runtime)
        guard let voice = runtime.catalog.resolve(voiceName) else {
            throw TTSError.internalError("Không có giọng nào dùng được trong voices_v3_turbo.json")
        }

        let total = CFAbsoluteTimeGetCurrent()
        let phonemeStart = CFAbsoluteTimeGetCurrent()
        let phonemes = runtime.g2p.phonemes(for: text)
        let phonemeIDs = runtime.tokenizer.encode(text: phonemes)
        let phonemeSeconds = CFAbsoluteTimeGetCurrent() - phonemeStart

        guard !phonemeIDs.isEmpty else {
            // Không có phoneme nào ⇒ trả im lặng hợp lệ. Bất biến của repo: không bao giờ đẩy chuỗi
            // rỗng vào engine, và không bao giờ trả về payload rỗng.
            return silence(for: boundaryKind, sampleRate: runtime.config.audioSampleRate)
        }

        let anchor = try resolveAnchor(for: voice, runtime: runtime)
        let (promptEmbeddings, promptRowCount) = try buildPrompt(
            phonemeIDs: phonemeIDs,
            voice: voice,
            anchor: anchor,
            runtime: runtime
        )

        var parameters = VieNeuDecodeLoop.Parameters()
        parameters.maxFrames = Self.frameCap(phonemeCount: phonemes.count)

        var profile = VieNeuDecodeLoop.Profile()
        let frames = try runtime.decodeLoop.generate(
            promptEmbeddings: promptEmbeddings,
            promptRowCount: promptRowCount,
            anchor: anchor,
            parameters: parameters,
            profile: &profile
        )

        guard !frames.isEmpty else {
            return silence(for: boundaryKind, sampleRate: runtime.config.audioSampleRate)
        }

        let codecStart = CFAbsoluteTimeGetCurrent()
        var samples = try decodeCodes(
            frames,
            codecSession: runtime.codecSession,
            outputNames: runtime.codecOutputNames,
            codebookCount: runtime.config.codebookCount
        )
        let codecSeconds = CFAbsoluteTimeGetCurrent() - codecStart

        // Đo **trước** khi chuẩn hoá: đây là cách phân biệt tiếng nói với tiếng ồn bằng số. Giọng
        // đọc cho rms/peak ~0.2 (tham chiếu trên engine Python: peak 0.58, rms 0.12); tiếng ồn
        // trắng cho ~0.5-0.7. Đo sau `normalise` thì peak luôn là 0.9 nên mất hết thông tin.
        var rawPeak: Float = 0
        var rawEnergy: Float = 0
        for value in samples where value.isFinite {
            rawPeak = max(rawPeak, abs(value))
            rawEnergy += value * value
        }
        let rawRMS = samples.isEmpty ? 0 : (rawEnergy / Float(samples.count)).squareRoot()

        normalise(&samples)
        appendBoundarySilence(&samples, boundaryKind: boundaryKind, sampleRate: runtime.config.audioSampleRate)

        let wav = WAVEncoder.encodePCM16(
            samples: samples,
            sampleRate: runtime.config.audioSampleRate,
            channels: 1
        )
        let duration = Double(samples.count) / Double(runtime.config.audioSampleRate)
        let elapsed = CFAbsoluteTimeGetCurrent() - total

        let frameCount = max(1, profile.frameCount)
        AppLogger.shared.log(
            """
            🗣️ [VieNeu] \(String(format: "%.2f", duration))s audio trong \(String(format: "%.2f", elapsed))s \
            (RTF \(String(format: "%.2f", elapsed / max(0.001, duration)))) \
            frames=\(profile.frameCount) eos=\(profile.hitEndOfSpeech) prompt=\(promptRowCount) \
            g2p=\(String(format: "%.0f", phonemeSeconds * 1000))ms \
            prefill=\(String(format: "%.0f", profile.prefillSeconds * 1000))ms \
            codec=\(String(format: "%.0f", codecSeconds * 1000))ms \
            acoustic=\(String(format: "%.2f", profile.acousticSeconds / Double(frameCount) * 1000))ms/frame \
            decode=\(String(format: "%.2f", profile.decodeSeconds / Double(frameCount) * 1000))ms/frame \
            sample=\(String(format: "%.2f", profile.samplingSeconds / Double(frameCount) * 1000))ms/frame \
            rawPeak=\(String(format: "%.3f", rawPeak)) rawRms=\(String(format: "%.3f", rawRMS)) \
            rmsPeak=\(String(format: "%.2f", rawPeak > 0 ? rawRMS / rawPeak : 0))
            """
        )
        return (wav, duration)
    }

    // MARK: - Prompt

    /// Trần frame theo độ dài phoneme, chống chunk ngắn "nói thêm".
    ///
    /// Cùng công thức với engine tham chiếu: `24 + 2.0 × số ký tự phoneme`, chặn trên ở 300 frame
    /// (24 giây audio ở 12.5 frame/giây). Trần cố định kiểu 150 frame là sai theo cả hai chiều —
    /// chunk ngắn vẫn được phép lan dài, chunk dài lại bị cắt giữa câu.
    static func frameCap(phonemeCount: Int) -> Int {
        min(300, 24 + Int((2.0 * Double(phonemeCount)).rounded(.up)))
    }

    /// Prompt 2D `(T, n_vq + 1)` được nhúng thành `(1, T, hidden)`.
    ///
    /// Cột 0 là token text, 16 cột sau là code audio. Các hàng text để code là `audio_pad`; sau đó là
    /// các hàng tham chiếu của giọng với token `audio_ref_slot` ở cột 0.
    ///
    /// Token dẫn đầu **luôn** là `defaultStyleTokenID` (16). Không dùng nhãn phong cách trong file
    /// giọng: id 13..42 là ô dự trữ random-init chưa train, `tin_tuc` (17) và `doc_truyen` (18) đều
    /// nằm trong đó.
    func buildPrompt(
        phonemeIDs: [Int64],
        voice: VieNeuVoice,
        anchor: [Float]?,
        runtime: Runtime
    ) throws -> ([Float], Int) {
        let config = runtime.config
        let hidden = config.hiddenSize

        var textTokens: [Int] = [config.defaultStyleTokenID, config.textPromptStartTokenID]
        textTokens.append(contentsOf: phonemeIDs.map(Int.init))
        textTokens.append(config.textPromptEndTokenID)

        let referenceRows = voice.referenceCodes.count
        let rowCount = textTokens.count + referenceRows

        guard rowCount + 8 <= config.maxPositionEmbeddings else {
            throw TTSError.internalError(
                "Prompt \(rowCount) hàng vượt max_position_embeddings \(config.maxPositionEmbeddings); cần chia chunk ngắn hơn"
            )
        }

        var embeddings = [Float](repeating: 0, count: rowCount * hidden)
        for (index, token) in textTokens.enumerated() {
            try runtime.tables.writeRowEmbedding(
                textToken: token,
                audioCodes: nil,
                anchor: anchor,
                into: &embeddings,
                rowOffset: index * hidden
            )
        }
        for (offset, codes) in voice.referenceCodes.enumerated() {
            try runtime.tables.writeRowEmbedding(
                textToken: config.audioReferenceSlotTokenID,
                audioCodes: codes[0..<codes.count],
                anchor: anchor,
                into: &embeddings,
                rowOffset: (textTokens.count + offset) * hidden
            )
        }
        return (embeddings, rowCount)
    }

    func resolveAnchor(for voice: VieNeuVoice, runtime: Runtime) throws -> [Float]? {
        guard runtime.config.usesSpeakerEmbedding else { return nil }
        runtimeLock.lock()
        if let cached = anchorCache[voice.name] {
            runtimeLock.unlock()
            return cached
        }
        runtimeLock.unlock()

        let anchor = try runtime.tables.speakerAnchor(for: voice.speakerEmbedding)
        runtimeLock.lock()
        anchorCache[voice.name] = anchor
        runtimeLock.unlock()
        return anchor
    }
}
