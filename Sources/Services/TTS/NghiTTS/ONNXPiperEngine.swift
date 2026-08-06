import Foundation
import OnnxRuntimeBindings

internal struct TTSPCMChunkPayload: Sendable {
    internal let samples: [Float]
    internal let sampleRate: Int
    internal let chunkIndex: Int
    internal let totalChunks: Int
    internal let isLast: Bool
}

final class ONNXPiperEngine: PiperEngine {
    private struct PiperConfig: Decodable {
        struct AudioConfig: Decodable {
            let sample_rate: Int?
        }
        let audio: AudioConfig?
        let phoneme_id_map: [String: [Int]]?
    }

    private struct CachedRuntime {
        let modelURL: URL
        let configURL: URL
        let env: ORTEnv
        let session: ORTSession
        let phonemeIdMap: [String: [Int]]
        let sampleRate: Int
        let padId: Int
        let bosId: Int
        let eosId: Int
        let inputNames: [String]
        let firstOutputName: String
    }

    private typealias ChunkPayloadHandler = @Sendable (TTSPCMChunkPayload) async throws -> Void

    private var cached: CachedRuntime?
    private let sessionLock = NSLock()

    private func getRuntime(modelONNX: URL, modelConfig: URL) throws -> CachedRuntime {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if let cached = cached,
           cached.modelURL == modelONNX,
           cached.configURL == modelConfig {
            return cached
        }

        guard let configData = try? Data(contentsOf: modelConfig) else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Không thể đọc cấu hình mô hình tại \(modelConfig.lastPathComponent)")
            throw TTSError.internalError("Cannot read Piper config file: \(modelConfig.lastPathComponent)")
        }

        guard let config = try? JSONDecoder().decode(PiperConfig.self, from: configData),
              let phonemeIdMap = config.phoneme_id_map else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Không thể phân tích cú pháp JSON cấu hình.")
            throw TTSError.internalError("Failed to parse Piper config file: \(modelConfig.lastPathComponent)")
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        let session = try ORTSession(env: env, modelPath: modelONNX.path, sessionOptions: options)
        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()
        guard let firstOutputName = outputNames.first else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Model không có output names.")
            throw TTSError.internalError("Model has no output names.")
        }

        let runtime = CachedRuntime(
            modelURL: modelONNX,
            configURL: modelConfig,
            env: env,
            session: session,
            phonemeIdMap: phonemeIdMap,
            sampleRate: config.audio?.sample_rate ?? 22050,
            padId: phonemeIdMap["_"]?.first ?? 0,
            bosId: phonemeIdMap["^"]?.first ?? 1,
            eosId: phonemeIdMap["$"]?.first ?? 2,
            inputNames: inputNames,
            firstOutputName: firstOutputName
        )
        cached = runtime
        return runtime
    }

    private struct TextChunk {
        let text: String
        let punctuation: String
    }

    private func chunkTextWithPunctuation(_ text: String) -> [TextChunk] {
        let nsString = text as NSString
        let pattern = "(?:\\r?\\n)+|(?<!\\d)\\.|\\.(?!\\d)|!|\\?|(?<!\\d),|,(?!\\d)|;|:|[\"「」『』【】［］()\\{\\}\\[\\]]"

        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return [TextChunk(text: text, punctuation: "")]
        }

        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        var chunks: [TextChunk] = []
        var lastIndex = 0

        for match in matches {
            let range = NSRange(location: lastIndex, length: match.range.location - lastIndex)
            let chunkText = nsString.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines)
            let punctuation = nsString.substring(with: match.range)

            if !chunkText.isEmpty {
                chunks.append(TextChunk(text: chunkText, punctuation: punctuation))
            } else if !chunks.isEmpty {
                let lastIdx = chunks.count - 1
                let updatedPunct = chunks[lastIdx].punctuation + punctuation
                chunks[lastIdx] = TextChunk(text: chunks[lastIdx].text, punctuation: updatedPunct)
            }

            lastIndex = match.range.location + match.range.length
        }

        if lastIndex < nsString.length {
            let chunkText = nsString.substring(from: lastIndex).trimmingCharacters(in: .whitespacesAndNewlines)
            if !chunkText.isEmpty {
                chunks.append(TextChunk(text: chunkText, punctuation: ""))
            }
        }

        return chunks
    }

    private func pauseDuration(for punctuation: String) -> Double {
        let trimmed = punctuation.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            if punctuation.contains("\n") || punctuation.contains("\r") {
                let val = UserDefaults.standard.double(forKey: "newlinePauseDuration")
                return val > 0 ? val : 0.4
            }
            return 0.0
        }

        if trimmed.contains(".") || trimmed.contains("!") || trimmed.contains("?") {
            let val = UserDefaults.standard.double(forKey: "sentencePauseDuration")
            return val > 0 ? val : 0.3
        }

        if trimmed.contains("\"") ||
           trimmed.contains("(") || trimmed.contains(")") ||
           trimmed.contains("[") || trimmed.contains("]") ||
           trimmed.contains("{") || trimmed.contains("}") ||
           trimmed.contains("「") || trimmed.contains("」") ||
           trimmed.contains("『") || trimmed.contains("』") ||
           trimmed.contains("【") || trimmed.contains("】") ||
           trimmed.contains("［") || trimmed.contains("］") {
            let val = UserDefaults.standard.double(forKey: "bracketPauseDuration")
            return val > 0 ? val : 0.1
        }

        if trimmed.contains(",") || trimmed.contains(";") || trimmed.contains(":") {
            let val = UserDefaults.standard.double(forKey: "phrasePauseDuration")
            return val > 0 ? val : 0.15
        }

        return 0.0
    }

    private func trimSilence(_ samples: [Float], threshold: Float = 0.002, minSamples: Int = 441) -> [Float] {
        guard !samples.isEmpty else { return [] }
        var start = 0
        var end = samples.count - 1
        while start < end && abs(samples[start]) < threshold { start += 1 }
        while end > start && abs(samples[end]) < threshold { end -= 1 }
        start = max(0, start - minSamples)
        end = min(samples.count - 1, end + minSamples)
        if start > end { return [] }
        return Array(samples[start...end])
    }

    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double, boundaryKind: TTSBoundaryKind = .paragraphEnd) async throws -> Data {
        try await synthesizeInternal(
            text: text,
            modelONNX: modelONNX,
            modelConfig: modelConfig,
            speed: speed,
            boundaryKind: boundaryKind,
            onChunkPayload: nil
        )
    }

    func synthesizeStream(
        text: String,
        modelONNX: URL,
        modelConfig: URL,
        speed: Double,
        onChunkPayload: @escaping @Sendable (TTSPCMChunkPayload) async throws -> Void
    ) async throws -> Data {
        try await synthesizeInternal(
            text: text,
            modelONNX: modelONNX,
            modelConfig: modelConfig,
            speed: speed,
            boundaryKind: .paragraphEnd,
            onChunkPayload: onChunkPayload
        )
    }

    private func synthesizeInternal(
        text: String,
        modelONNX: URL,
        modelConfig: URL,
        speed: Double,
        boundaryKind: TTSBoundaryKind,
        onChunkPayload: ChunkPayloadHandler?
    ) async throws -> Data {
        let runtime = try getRuntime(modelONNX: modelONNX, modelConfig: modelConfig)
        let sampleRate = runtime.sampleRate
        let padId = runtime.padId
        let bosId = runtime.bosId
        let eosId = runtime.eosId
        let phonemeIdMap = runtime.phonemeIdMap
        let session = runtime.session
        let inputNames = runtime.inputNames
        let firstOutputName = runtime.firstOutputName

        let chunks = chunkTextWithPunctuation(text)
        guard !chunks.isEmpty else {
            throw TTSError.internalError("Text contains no speakable chunks.")
        }

        var mergedSamples: [Float] = []
        let minSamples = Int(Double(sampleRate) * 0.02)
        var lastGain: Float = 1.0

        for (index, chunk) in chunks.enumerated() {
            try Task.checkCancellation()
            let isLastChunk = (index == chunks.count - 1)
            let processedText = chunk.text
            let rawPhonemes = try EspeakPhonemizer.phonemize(text: processedText)
            let phonemes = rawPhonemes
                .replacingOccurrences(of: "(en)", with: "")
                .replacingOccurrences(of: "(vi)", with: "")

            var phonemeIds: [Int64] = []
            phonemeIds.append(Int64(bosId))
            phonemeIds.append(Int64(padId))

            for scalar in phonemes.unicodeScalars {
                let phonemeStr = String(scalar)
                if let ids = phonemeIdMap[phonemeStr] {
                    for id in ids {
                        phonemeIds.append(Int64(id))
                        phonemeIds.append(Int64(padId))
                    }
                } else {
                    AppLogger.shared.log("Warning: Missing phoneme mapping for: \(phonemeStr)")
                }
            }
            phonemeIds.append(Int64(eosId))

            let inputShape: [NSNumber] = [1, NSNumber(value: phonemeIds.count)]
            let inputData = phonemeIds.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return Data() }
                return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Int64>.size)
            }
            let inputNSMutableData = NSMutableData(data: inputData)
            let inputTensor = try ORTValue(
                tensorData: inputNSMutableData,
                elementType: ORTTensorElementDataType.int64,
                shape: inputShape
            )

            let inputLengthValue: Int64 = Int64(phonemeIds.count)
            let lengthShape: [NSNumber] = [1]
            let lengthData = withUnsafePointer(to: inputLengthValue) { ptr in
                Data(bytes: ptr, count: MemoryLayout<Int64>.size)
            }
            let lengthNSMutableData = NSMutableData(data: lengthData)
            let lengthTensor = try ORTValue(
                tensorData: lengthNSMutableData,
                elementType: ORTTensorElementDataType.int64,
                shape: lengthShape
            )

            let noiseScale: Float = 0.667
            let lengthScale: Float = Float(1.0 / speed)
            let noiseW: Float = 0.8
            let scales = [noiseScale, lengthScale, noiseW]
            let scalesShape: [NSNumber] = [3]
            let scalesData = scales.withUnsafeBufferPointer { buffer in
                guard let baseAddress = buffer.baseAddress else { return Data() }
                return Data(bytes: baseAddress, count: buffer.count * MemoryLayout<Float>.size)
            }
            let scalesNSMutableData = NSMutableData(data: scalesData)
            let scalesTensor = try ORTValue(
                tensorData: scalesNSMutableData,
                elementType: ORTTensorElementDataType.float,
                shape: scalesShape
            )

            var feeds: [String: ORTValue] = [
                "input": inputTensor,
                "input_lengths": lengthTensor,
                "scales": scalesTensor
            ]

            var sidNSMutableData: NSMutableData? = nil
            if inputNames.contains("sid") {
                let speakerId: Int64 = 0
                let sidShape: [NSNumber] = [1]
                let sidData = withUnsafePointer(to: speakerId) { ptr in
                    Data(bytes: ptr, count: MemoryLayout<Int64>.size)
                }
                let data = NSMutableData(data: sidData)
                sidNSMutableData = data
                let sidTensor = try ORTValue(
                    tensorData: data,
                    elementType: ORTTensorElementDataType.int64,
                    shape: sidShape
                )
                feeds["sid"] = sidTensor
            }

            let outputs = try session.run(
                withInputs: feeds,
                outputNames: Set([firstOutputName]),
                runOptions: nil
            )
            try Task.checkCancellation()

            _ = inputNSMutableData
            _ = lengthNSMutableData
            _ = scalesNSMutableData
            if let sidNSMutableData {
                _ = sidNSMutableData
            }

            guard let outputValue = outputs[firstOutputName] else {
                AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Model không trả về speech tensor '\(firstOutputName)'.")
                throw TTSError.internalError("Model did not return speech '\(firstOutputName)' tensor.")
            }

            let outputData = try outputValue.tensorData() as Data
            let samplesCount = outputData.count / MemoryLayout<Float>.size
            var chunkSamples = [Float](repeating: 0.0, count: samplesCount)
            _ = chunkSamples.withUnsafeMutableBytes { samplesBuffer in
                outputData.copyBytes(to: samplesBuffer)
            }

            var trimmedChunk = trimSilence(chunkSamples, threshold: 0.002, minSamples: minSamples)

            var maxVal: Float = 1e-9
            for s in trimmedChunk { maxVal = max(maxVal, abs(s)) }
            let rawGain = min(3.5, 0.9 / maxVal)
            let maxGainStep: Float = 1.5
            let smoothedGain = max(lastGain / maxGainStep, min(lastGain * maxGainStep, rawGain))
            lastGain = smoothedGain
            for i in 0..<trimmedChunk.count {
                trimmedChunk[i] *= smoothedGain
            }

            if !isLastChunk {
                let pauseDurationSec = self.pauseDuration(for: chunk.punctuation)
                if pauseDurationSec > 0.0 {
                    let scaledDuration = pauseDurationSec / speed
                    let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
                    if silenceSamplesCount > 0 {
                        let silenceSamples = [Float](repeating: 0.0, count: silenceSamplesCount)
                        trimmedChunk.append(contentsOf: silenceSamples)
                    }
                }
            } else if boundaryKind == .paragraphEnd || boundaryKind == .chapterEnd {
                let paragraphPauseSec = UserDefaults.standard.double(forKey: "paragraphPauseDuration")
                let actualParagraphPause = paragraphPauseSec > 0 ? paragraphPauseSec : 0.5
                let scaledParagraphPause = actualParagraphPause / max(0.1, speed)
                let paragraphSilenceSamplesCount = Int(Double(sampleRate) * scaledParagraphPause)
                if paragraphSilenceSamplesCount > 0 {
                    let silenceSamples = [Float](repeating: 0.0, count: paragraphSilenceSamplesCount)
                    trimmedChunk.append(contentsOf: silenceSamples)
                }
            }

            if let onChunkPayload {
                let payload = TTSPCMChunkPayload(
                    samples: trimmedChunk,
                    sampleRate: sampleRate,
                    chunkIndex: index,
                    totalChunks: chunks.count,
                    isLast: isLastChunk
                )
                try Task.checkCancellation()
                try await onChunkPayload(payload)
                try Task.checkCancellation()
            }

            mergedSamples.append(contentsOf: trimmedChunk)
        }

        return WAVEncoder.encodePCM16(
            samples: mergedSamples,
            sampleRate: sampleRate,
            channels: 1
        )
    }
}
