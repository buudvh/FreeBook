import Foundation

protocol PiperEngine {
    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double) async throws -> Data
}

final class PiperTTSService {
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

    func synthesize(text: String, voice: String) async throws -> Data {
        let voiceId = voice.toASCIIID
        let modelONNX = modelStore.modelURL(for: voiceId, extension: "onnx")
        let modelConfig = modelStore.modelURL(for: voiceId, extension: "onnx.json")

        guard FileManager.default.fileExists(atPath: modelONNX.path),
              FileManager.default.fileExists(atPath: modelConfig.path) else {
            throw TTSError.modelNotCached("Model '\(voice)' is not cached. Call /v1/models/prefetch first.")
        }

        syncQueue.sync { _currentModel = voice }
        
        let speed = 1.0
        // Nếu không chứa ký tự chữ/số nào, tạo khoảng lặng chờ tương đương dấu câu và trả về ngay
        if text.rangeOfCharacter(from: .alphanumerics) == nil {
            let sampleRate = 22050 // Tần số mẫu mặc định của model
            let phrasePause = UserDefaults.standard.double(forKey: "phrasePauseDuration")
            let sentencePause = UserDefaults.standard.double(forKey: "sentencePauseDuration")
            let hasSentencePunct = text.contains(".") || text.contains("!") || text.contains("?")
            let pauseDuration = hasSentencePunct ? (sentencePause > 0 ? sentencePause : 0.4) : (phrasePause > 0 ? phrasePause : 0.2)
            
            let scaledDuration = pauseDuration / speed
            let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
            let silenceSamples = [Float](repeating: 0.0, count: max(0, silenceSamplesCount))
            
            return WAVEncoder.encodePCM16(
                samples: silenceSamples,
                sampleRate: sampleRate,
                channels: 1
            )
        }

        let preprocessedText = await TextPreprocessor.shared.preprocess(text)
        
        return try await engine.synthesize(
            text: preprocessedText,
            modelONNX: modelONNX,
            modelConfig: modelConfig,
            speed: speed
        )
    }
}

struct UnavailablePiperEngine: PiperEngine {
    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double) async throws -> Data {
        throw TTSError.engineUnavailable(
            "Native Piper synthesis is not linked yet. Add ONNX Runtime Mobile plus an eSpeak phonemizer binding, then implement PiperEngine."
        )
    }
}
