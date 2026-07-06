import Foundation
import OnnxRuntimeBindings

final class ONNXPiperEngine: PiperEngine {
    private struct PiperConfig: Decodable {
        struct AudioConfig: Decodable {
            let sample_rate: Int?
        }
        let audio: AudioConfig?
        let phoneme_id_map: [String: [Int]]?
    }

    private struct CachedSession {
        let modelURL: URL
        let env: ORTEnv
        let session: ORTSession
    }

    private var cached: CachedSession?
    private let sessionLock = NSLock()

    private func getSession(modelONNX: URL) throws -> (ORTEnv, ORTSession) {
        sessionLock.lock()
        defer { sessionLock.unlock() }

        if let cached = cached, cached.modelURL == modelONNX {
            return (cached.env, cached.session)
        }

        let env = try ORTEnv(loggingLevel: .warning)
        let options = try ORTSessionOptions()
        let session = try ORTSession(env: env, modelPath: modelONNX.path, sessionOptions: options)

        cached = CachedSession(modelURL: modelONNX, env: env, session: session)
        return (env, session)
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

    private func trimSilence(_ samples: [Float], threshold: Float = 0.0005, minSamples: Int = 2205) -> [Float] {
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

    private func normalizePeak(_ samples: inout [Float], target: Float = 0.9) {
        guard !samples.isEmpty else { return }
        var maxVal: Float = 1e-9
        for s in samples { maxVal = max(maxVal, abs(s)) }
        let gain = min(4.0, target / maxVal)
        for i in 0..<samples.count {
            samples[i] *= gain
        }
    }

    func synthesize(text: String, modelONNX: URL, modelConfig: URL, speed: Double) async throws -> Data {
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Bắt đầu tổng hợp âm thanh...")
        // 1. Đọc và phân tích cú pháp tệp cấu hình JSON
        guard let configData = try? Data(contentsOf: modelConfig) else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Không thể đọc cấu hình mô hình tại \(modelConfig.lastPathComponent)")
            throw TTSError.internalError("Cannot read Piper config file: \(modelConfig.lastPathComponent)")
        }
        
        guard let config = try? JSONDecoder().decode(PiperConfig.self, from: configData),
              let phonemeIdMap = config.phoneme_id_map else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Không thể phân tích cú pháp JSON cấu hình.")
            throw TTSError.internalError("Failed to parse Piper config file: \(modelConfig.lastPathComponent)")
        }
        
        let sampleRate = config.audio?.sample_rate ?? 22050
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Tần số mẫu: \(sampleRate)")
        
        // Xác định các ký tự đặc biệt
        let padId = phonemeIdMap["_"]?.first ?? 0
        let bosId = phonemeIdMap["^"]?.first ?? 1
        let eosId = phonemeIdMap["$"]?.first ?? 2
        
        // Lấy môi trường và Session từ cache (hoặc khởi tạo mới nếu đổi model)
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Đang nạp session cho model: \(modelONNX.lastPathComponent)...")
        let (_, session) = try getSession(modelONNX: modelONNX)
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Đã nạp session thành công.")
        
        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()
        guard let firstOutputName = outputNames.first else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] LỖI: Model không có output names.")
            throw TTSError.internalError("Model has no output names.")
        }
        
        // Tách câu để xử lý tuần tự kèm theo thông tin dấu câu để chèn khoảng lặng tĩnh
        let chunks = chunkTextWithPunctuation(text)
        guard !chunks.isEmpty else {
            AppLogger.shared.log("🤖 [ONNXPiperEngine] Văn bản rỗng hoặc chỉ toàn dấu câu, trả về khoảng lặng.")
            return WAVEncoder.encodePCM16(samples: [], sampleRate: sampleRate, channels: 1)
        }
        
        var mergedSamples: [Float] = []
        let minSamples = Int(Double(sampleRate) * 0.02) // 20ms safety margin
        
        for (index, chunk) in chunks.enumerated() {
            // Chuyển văn bản sang âm vị sử dụng eSpeak NG cho từng câu
            let processedText = chunk.text
            AppLogger.shared.log("🤖 [ONNXPiperEngine] Đang xử lý câu \(index + 1)/\(chunks.count): '\(processedText)'")
            
            AppLogger.shared.log("🤖 [ONNXPiperEngine] Gọi EspeakPhonemizer.phonemize...")
            let rawPhonemes = try EspeakPhonemizer.phonemize(text: processedText)
            AppLogger.shared.log("🤖 [ONNXPiperEngine] Gọi EspeakPhonemizer.phonemize xong: '\(rawPhonemes)'")
            
            // Làm sạch các ký tự điều khiển của eSpeak
            let phonemes = rawPhonemes
                .replacingOccurrences(of: "(en)", with: "")
                .replacingOccurrences(of: "(vi)", with: "")
            
            // Ánh xạ âm vị sang mảng Phoneme IDs theo chuẩn VITS (BOS, PAD, P1, PAD, P2, ..., EOS)
            var phonemeIds: [Int64] = []
            phonemeIds.append(Int64(bosId))
            phonemeIds.append(Int64(padId))
            
            // Duyệt theo từng Unicode Scalar để tránh tách sai các ký tự ghép trong IPA
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
            
            // Chuẩn bị các Tensor đầu vào
            // Input 1: "input" -> shape [1, phoneme_count]
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
            
            // Input 2: "input_lengths" -> shape [1]
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
            
            // Input 3: "scales" -> shape [3] -> [noise_scale, length_scale, noise_w]
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
            
            // Hỗ trợ model đa giọng đọc (Multi-speaker) nếu có yêu cầu "sid" (Speaker ID)
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
            
            // Chạy suy luận (Run Inference)
            AppLogger.shared.log("🤖 [ONNXPiperEngine] Đang chạy session.run cho câu \(index + 1)...")
            let outputs = try session.run(
                withInputs: feeds,
                outputNames: Set([firstOutputName]),
                runOptions: nil
            )
            AppLogger.shared.log("🤖 [ONNXPiperEngine] session.run thành công cho câu \(index + 1).")
            
            // Kéo dài vòng đời của NSMutableData thủ công để tránh ARC giải phóng trước session.run kết thúc
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
            
            // Chuyển đổi dữ liệu sang mảng PCM Float [-1.0, 1.0]
            let samplesCount = outputData.count / MemoryLayout<Float>.size
            var chunkSamples = [Float](repeating: 0.0, count: samplesCount)
            _ = chunkSamples.withUnsafeMutableBytes { samplesBuffer in
                outputData.copyBytes(to: samplesBuffer)
            }
            
            // Cắt khoảng lặng cho phân đoạn
            let trimmedChunk = trimSilence(chunkSamples, threshold: 0.002, minSamples: minSamples)
            mergedSamples.append(contentsOf: trimmedChunk)
            
            // Chèn khoảng lặng tĩnh dựa theo dấu câu và tốc độ (chỉ chèn nếu chưa phải là chunk cuối)
            if index < chunks.count - 1 {
                let pauseDurationSec = self.pauseDuration(for: chunk.punctuation)
                if pauseDurationSec > 0.0 {
                    let scaledDuration = pauseDurationSec / speed
                    let silenceSamplesCount = Int(Double(sampleRate) * scaledDuration)
                    if silenceSamplesCount > 0 {
                        let silenceSamples = [Float](repeating: 0.0, count: silenceSamplesCount)
                        mergedSamples.append(contentsOf: silenceSamples)
                    }
                }
            }
        }
        
        // Chèn khoảng lặng tĩnh ở cuối đoạn (paragraph pause) để tạo khoảng nghỉ tự nhiên và tránh bị cắt chữ khi player dừng đột ngột
        let paragraphPauseSec = UserDefaults.standard.double(forKey: "paragraphPauseDuration")
        let actualParagraphPause = paragraphPauseSec > 0 ? paragraphPauseSec : 0.5
        let scaledParagraphPause = actualParagraphPause / max(0.1, speed)
        let paragraphSilenceSamplesCount = Int(Double(sampleRate) * scaledParagraphPause)
        if paragraphSilenceSamplesCount > 0 {
            let silenceSamples = [Float](repeating: 0.0, count: paragraphSilenceSamplesCount)
            mergedSamples.append(contentsOf: silenceSamples)
        }
        
        // Chuẩn bị kết quả
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Chuẩn hóa đỉnh âm lượng...")
        // Chuẩn hóa đỉnh âm lượng
        normalizePeak(&mergedSamples, target: 0.9)
        
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Đang đóng gói thành tệp WAV...")
        // Đóng gói thành tệp WAV
        let wavData = WAVEncoder.encodePCM16(
            samples: mergedSamples,
            sampleRate: sampleRate,
            channels: 1
        )
        
        AppLogger.shared.log("🤖 [ONNXPiperEngine] Tổng hợp hoàn tất. Dung lượng: \(wavData.count) bytes")
        return wavData
    }
}
