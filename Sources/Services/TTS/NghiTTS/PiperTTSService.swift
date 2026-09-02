import Foundation

protocol PiperEngine {
    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double, boundaryKind: TTSBoundaryKind) async throws -> Data
}

final class PiperTTSService: @unchecked Sendable {
    private let modelStore: ModelStore
    private let engine: PiperEngine
    private let syncQueue = DispatchQueue(label: "PiperTTSService.sync")
    private var _currentModel: String?

    var currentModel: String? {
        return syncQueue.sync { _currentModel }
    }

    var engineStatus: String {
        "Piper ONNX C++ & eSpeak-NG local engine is active."
    }

    init(modelStore: ModelStore, engine: PiperEngine = ONNXPiperEngine()) {
        self.modelStore = modelStore
        self.engine = engine
    }

    func prepare(voice: String) async throws {
        guard let onnxEngine = engine as? ONNXPiperEngine else { return }
        let voiceId = voice.toASCIIID
        let modelONNX = modelStore.modelURL(for: voiceId, extension: "onnx")
        let modelConfig = modelStore.modelURL(for: voiceId, extension: "onnx.json")
        guard FileManager.default.fileExists(atPath: modelONNX.path),
              FileManager.default.fileExists(atPath: modelConfig.path) else {
            return
        }
        try await Task.detached(priority: .utility) {
            try onnxEngine.prepare(modelONNX: modelONNX, modelConfig: modelConfig)
        }.value
    }

    /// Tổng hợp một đoạn và chỉ trả WAV.
    ///
    /// Bỏ trống `synthesisKey` là an toàn: `synthesizeWithDuration` tự sinh key mặc định nên
    /// request vẫn được gộp thay vì chạy ONNX hai lần cho cùng một đoạn text.
    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> Data {
        let result = try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
        )
        return result.data
    }

    /// Tổng hợp một đoạn, trả cả thời lượng PCM.
    ///
    /// `synthesisKey == nil` **không** còn nghĩa là "không gộp request": key được sinh tự động từ
    /// `(file model, tốc độ, loại ranh giới, nội dung text)` để `PiperSynthesisCoordinator` luôn
    /// gộp được hai đường cùng yêu cầu một đoạn text thay vì chạy ONNX hai lần đầy đủ.
    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let effectiveKey = synthesisKey ?? makeDefaultSynthesisKey(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            streaming: false
        )
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey
        ) { [weak self] in
            guard let self = self else { throw CancellationError() }
            return try await self.executeInternalSynthesisWithDuration(text: text, voice: voice, speed: speed, boundaryKind: boundaryKind)
        }
        return (
            data: payload.data,
            pcmDuration: payload.pcmDuration,
            queueWaitMs: payload.queueWaitMs,
            synthesisMs: payload.synthesisMs
        )
    }

    func synthesizeStream(
        text: String,
        voice: String,
        speed: Double,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil,
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        let effectiveKey = synthesisKey ?? makeDefaultSynthesisKey(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: .paragraphEnd,
            streaming: true
        )
        // Vẫn đặt key để `promote(synthesisKey:)` nâng được mức ưu tiên, nhưng **cấm gộp**:
        // closure `onChunkPayload` nằm trong `work` của waiter đầu tiên, waiter thứ hai gộp vào sẽ
        // không bao giờ được gọi lại ⇒ mất sạch chunk PCM và mất luôn double-buffering.
        return try await PiperSynthesisCoordinator.shared.enqueue(
            priority: priority,
            requestID: requestID,
            synthesisKey: effectiveKey,
            allowsCoalescing: false
        ) { [weak self] in
            guard let self = self else { throw CancellationError() }
            return try await self.executeInternalSynthesisStream(
                text: text,
                voice: voice,
                speed: speed,
                onChunkPayload: onChunkPayload
            )
        }
    }

    /// Sinh `synthesisKey` mặc định khi caller không truyền.
    ///
    /// Gộp đúng bốn thứ quyết định kết quả tổng hợp: file model (suy ra từ `voiceId`), tốc độ,
    /// loại ranh giới và nội dung text. `engine` mang thêm nhãn `stream` để key của đường stream
    /// không bao giờ trùng key của đường thường. Tiền tố `auto-` để phân biệt với key tường minh
    /// do `TTSSynthesisIdentity.computeKey` sinh ở tầng trên (dạng 64 ký tự hex).
    private func makeDefaultSynthesisKey(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        streaming: Bool
    ) -> String {
        let voiceId = voice.toASCIIID
        let modelPath = modelStore.modelURL(for: voiceId, extension: "onnx").path
        let digest = TTSSynthesisIdentity.computeKey(
            chapterURL: modelPath,
            chapterIndex: -1,
            paragraphIndex: -1,
            finalText: text,
            engine: streaming ? "nghitts-stream" : "nghitts",
            voice: "\(voiceId)|speed=\(speed)|boundary=\(boundaryKind.rawValue)"
        )
        return "auto-\(digest)"
    }

    private func executeInternalSynthesis(text: String, voice: String, speed: Double, boundaryKind: TTSBoundaryKind) async throws -> Data {
        let result = try await executeInternalSynthesisWithDuration(text: text, voice: voice, speed: speed, boundaryKind: boundaryKind)
        return result.data
    }

    private func executeInternalSynthesisWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind
    ) async throws -> PiperSynthesisPayload {
        let voiceId = voice.toASCIIID
        let modelONNX = modelStore.modelURL(for: voiceId, extension: "onnx")
        let modelConfig = modelStore.modelURL(for: voiceId, extension: "onnx.json")

        guard FileManager.default.fileExists(atPath: modelONNX.path),
              FileManager.default.fileExists(atPath: modelConfig.path) else {
            throw TTSError.modelNotCached("Model '\(voice)' is not cached. Call /v1/models/prefetch first.")
        }

        syncQueue.sync { _currentModel = voice }
        
        if Self.isUnspeakable(text) {
            let spec = Self.makeSilenceSpec(text: text, speed: speed)
            let silenceData = WAVEncoder.encodePCM16(
                samples: spec.samples,
                sampleRate: spec.sampleRate,
                channels: 1
            )
            return PiperSynthesisPayload(data: silenceData, pcmDuration: spec.pcmDuration)
        }

        let preprocessedText = await TextPreprocessor.shared.preprocess(text)
        if Self.isUnspeakable(preprocessedText) {
            let spec = Self.makeSilenceSpec(text: text, speed: speed)
            let silenceData = WAVEncoder.encodePCM16(
                samples: spec.samples,
                sampleRate: spec.sampleRate,
                channels: 1
            )
            return PiperSynthesisPayload(data: silenceData, pcmDuration: spec.pcmDuration)
        }
        
        if let onnxEngine = engine as? ONNXPiperEngine {
            let res = try await onnxEngine.synthesizeWithDuration(
                text: preprocessedText,
                modelONNX: modelONNX,
                modelConfig: modelConfig,
                speed: speed,
                boundaryKind: boundaryKind
            )
            return PiperSynthesisPayload(data: res.data, pcmDuration: res.pcmDuration)
        } else {
            let wavData = try await engine.synthesize(
                text: preprocessedText,
                modelONNX: modelONNX,
                modelConfig: modelConfig,
                speed: speed,
                boundaryKind: boundaryKind
            )
            let duration = WAVEncoder.duration(of: wavData)
            return PiperSynthesisPayload(data: wavData, pcmDuration: duration)
        }
    }

    struct SilenceSpec: Sendable {
        let samples: [Float]
        let sampleRate: Int
        let pcmDuration: Double
    }

    struct SilenceStreamingPayload: Sendable {
        let chunkPayload: TTSPCMChunkPayload
        let wavData: Data
    }

    /// Bộ nhớ đệm cho payload im lặng.
    ///
    /// Đoạn im lặng chỉ phụ thuộc `(sampleRate, số sample)` — mọi sample đều là 0 — nên `[Float]` và
    /// WAV sinh ra là **hằng**. Trước đây mỗi khoảng nghỉ trong chương đều cấp phát lại mảng rồi encode
    /// lại WAV; một chương dài có hàng nghìn khoảng nghỉ. Cache là chính xác tuyệt đối, không đổi hành vi.
    private static let silenceCacheLock = NSLock()
    private static var silenceCache: [String: (samples: [Float], wav: Data)] = [:]
    private static let silenceCacheLimit = 12

    private static func cachedSilence(sampleRate: Int, count: Int) -> (samples: [Float], wav: Data) {
        let key = "\(sampleRate)|\(count)"
        silenceCacheLock.lock()
        if let hit = silenceCache[key] {
            silenceCacheLock.unlock()
            return hit
        }
        silenceCacheLock.unlock()

        let samples = [Float](repeating: 0.0, count: max(0, count))
        let wav = WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1)

        silenceCacheLock.lock()
        if silenceCache.count >= silenceCacheLimit {
            silenceCache.removeAll()
        }
        silenceCache[key] = (samples, wav)
        silenceCacheLock.unlock()
        return (samples, wav)
    }

    static func makeSilenceSpec(
        text: String,
        speed: Double,
        sampleRate: Int = 22050,
        phrasePause: Double? = nil,
        sentencePause: Double? = nil
    ) -> SilenceSpec {
        let defaults = UserDefaults.standard
        let pPause = phrasePause ?? defaults.double(forKey: "phrasePauseDuration")
        let sPause = sentencePause ?? defaults.double(forKey: "sentencePauseDuration")
        let hasSentencePunct = text.contains(".") || text.contains("!") || text.contains("?")
        let pauseDuration = hasSentencePunct ? (sPause > 0 ? sPause : 0.3) : (pPause > 0 ? pPause : 0.15)

        let effectiveSpeed = max(0.1, speed)
        let scaledDuration = pauseDuration / effectiveSpeed
        let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
        let silenceSamples = cachedSilence(sampleRate: sampleRate, count: silenceSamplesCount).samples
        let pcmDur = Double(silenceSamplesCount) / Double(sampleRate)
        return SilenceSpec(samples: silenceSamples, sampleRate: sampleRate, pcmDuration: pcmDur)
    }

    static func buildSilenceStreamingPayload(
        text: String,
        speed: Double,
        sampleRate: Int = 22050,
        phrasePause: Double? = nil,
        sentencePause: Double? = nil
    ) -> SilenceStreamingPayload {
        let spec = makeSilenceSpec(text: text, speed: speed, sampleRate: sampleRate, phrasePause: phrasePause, sentencePause: sentencePause)
        let payload = TTSPCMChunkPayload(
            samples: spec.samples,
            sampleRate: spec.sampleRate,
            chunkIndex: 0,
            totalChunks: 1,
            isLast: true
        )
        let wavData = cachedSilence(sampleRate: spec.sampleRate, count: spec.samples.count).wav
        return SilenceStreamingPayload(chunkPayload: payload, wavData: wavData)
    }

    static func isUnspeakable(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty || trimmed.rangeOfCharacter(from: .alphanumerics) == nil
    }

    private func executeInternalSynthesisStream(
        text: String,
        voice: String,
        speed: Double,
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        guard let onnxEngine = engine as? ONNXPiperEngine else {
            throw TTSError.engineUnavailable("Streaming is not supported by current PiperEngine implementation.")
        }

        let voiceId = voice.toASCIIID
        let modelONNX = modelStore.modelURL(for: voiceId, extension: "onnx")
        let modelConfig = modelStore.modelURL(for: voiceId, extension: "onnx.json")

        guard FileManager.default.fileExists(atPath: modelONNX.path),
              FileManager.default.fileExists(atPath: modelConfig.path) else {
            throw TTSError.modelNotCached("Model '\(voice)' is not cached. Call /v1/models/prefetch first.")
        }

        syncQueue.sync { _currentModel = voice }

        if Self.isUnspeakable(text) {
            let streamingSilence = Self.buildSilenceStreamingPayload(text: text, speed: speed)
            try await onChunkPayload(streamingSilence.chunkPayload)
            return streamingSilence.wavData
        }

        let preprocessedText = await TextPreprocessor.shared.preprocess(text)
        if Self.isUnspeakable(preprocessedText) {
            let streamingSilence = Self.buildSilenceStreamingPayload(text: text, speed: speed)
            try await onChunkPayload(streamingSilence.chunkPayload)
            return streamingSilence.wavData
        }

        return try await onnxEngine.synthesizeStream(
            text: preprocessedText,
            modelONNX: modelONNX,
            modelConfig: modelConfig,
            speed: speed,
            onChunkPayload: onChunkPayload
        )
    }
}
