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

    func synthesize(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .high,
        requestID: UUID = UUID()
    ) async throws -> Data {
        let result = try await synthesizeWithDuration(
            text: text,
            voice: voice,
            speed: speed,
            boundaryKind: boundaryKind,
            priority: priority,
            requestID: requestID
        )
        return result.data
    }

    func synthesizeWithDuration(
        text: String,
        voice: String,
        speed: Double,
        boundaryKind: TTSBoundaryKind = .paragraphEnd,
        priority: SynthesisPriority = .high,
        requestID: UUID = UUID()
    ) async throws -> (data: Data, pcmDuration: Double, queueWaitMs: Double, synthesisMs: Double) {
        let payload = try await PiperSynthesisCoordinator.shared.enqueuePayload(
            priority: priority,
            requestID: requestID
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
        priority: SynthesisPriority = .high,
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
        
        if text.rangeOfCharacter(from: .alphanumerics) == nil {
            let sampleRate = 22050
            let phrasePause = UserDefaults.standard.double(forKey: "phrasePauseDuration")
            let sentencePause = UserDefaults.standard.double(forKey: "sentencePauseDuration")
            let hasSentencePunct = text.contains(".") || text.contains("!") || text.contains("?")
            let pauseDuration = hasSentencePunct ? (sentencePause > 0 ? sentencePause : 0.3) : (phrasePause > 0 ? phrasePause : 0.15)
            
            let scaledDuration = pauseDuration / speed
            let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
            let silenceSamples = [Float](repeating: 0.0, count: max(0, silenceSamplesCount))
            let silenceData = WAVEncoder.encodePCM16(
                samples: silenceSamples,
                sampleRate: sampleRate,
                channels: 1
            )
            let pcmDur = Double(silenceSamplesCount) / Double(sampleRate)
            return PiperSynthesisPayload(data: silenceData, pcmDuration: pcmDur)
        }

        let preprocessedText = await TextPreprocessor.shared.preprocess(text)
        
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

        if text.rangeOfCharacter(from: .alphanumerics) == nil {
            let sampleRate = 22050
            let phrasePause = UserDefaults.standard.double(forKey: "phrasePauseDuration")
            let sentencePause = UserDefaults.standard.double(forKey: "sentencePauseDuration")
            let hasSentencePunct = text.contains(".") || text.contains("!") || text.contains("?")
            let pauseDuration = hasSentencePunct ? (sentencePause > 0 ? sentencePause : 0.3) : (phrasePause > 0 ? phrasePause : 0.15)

            let scaledDuration = pauseDuration / speed
            let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
            let silenceSamples = [Float](repeating: 0.0, count: max(0, silenceSamplesCount))

            let payload = TTSPCMChunkPayload(
                samples: silenceSamples,
                sampleRate: sampleRate,
                chunkIndex: 0,
                totalChunks: 1,
                isLast: true
            )
            try await onChunkPayload(payload)

            return WAVEncoder.encodePCM16(
                samples: silenceSamples,
                sampleRate: sampleRate,
                channels: 1
            )
        }

        let preprocessedText = await TextPreprocessor.shared.preprocess(text)

        return try await onnxEngine.synthesizeStream(
            text: preprocessedText,
            modelONNX: modelONNX,
            modelConfig: modelConfig,
            speed: speed,
            onChunkPayload: onChunkPayload
        )
    }
}

struct UnavailablePiperEngine: PiperEngine {
    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double, boundaryKind: TTSBoundaryKind = .paragraphEnd) async throws -> Data {
        throw TTSError.engineUnavailable(
            "Native Piper synthesis is not linked yet. Add ONNX Runtime Mobile plus an eSpeak phonemizer binding, then implement PiperEngine."
        )
    }
}
