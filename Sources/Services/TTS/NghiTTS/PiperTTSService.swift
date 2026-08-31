import Foundation

protocol PiperEngine {
    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double, boundaryKind: TTSBoundaryKind) async throws -> Data
}

final class PiperTTSService: LocalTTSSynthesizing, @unchecked Sendable {
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

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .demand,
        requestID: UUID = UUID(),
        synthesisKey: String? = nil
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID,
            synthesisKey: synthesisKey
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
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        return try await PiperSynthesisCoordinator.shared.enqueue(
            priority: priority,
            requestID: requestID
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
        let silenceSamples = [Float](repeating: 0.0, count: max(0, silenceSamplesCount))
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
        let wavData = WAVEncoder.encodePCM16(
            samples: spec.samples,
            sampleRate: spec.sampleRate,
            channels: 1
        )
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
