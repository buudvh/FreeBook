import Accelerate
import Foundation
import OnnxRuntimeBindings

/// Giải mã code audio và hậu xử lý sóng âm cho `ONNXVieNeuEngine`.
///
/// Tách khỏi file gốc vì file đó đã tới trần 400 dòng của `check_architecture.py`.
extension ONNXVieNeuEngine {

    /// `(1, T, 16)` code → sóng âm mono.
    ///
    /// Codec là RVQ **residual** 16 tầng nên phải đưa đủ 16 kênh. Cắt bớt bằng cách nhồi code 0 vào
    /// các tầng cuối là **sai**: code 0 không phải im lặng mà là một vector residual cụ thể, cộng
    /// thêm nó 8 lần chỉ làm tiếng đục và rè. Muốn giảm bitrate thật thì phải đưa decoder ít
    /// codebook hơn, không phải nhồi index 0.
    func decodeCodes(
        _ frames: [[Int32]],
        codecSession: ORTSession,
        outputNames: Set<String>,
        codebookCount: Int
    ) throws -> [Float] {
        var flat = [Int32](repeating: 0, count: frames.count * codebookCount)
        for (index, frame) in frames.enumerated() {
            for channel in 0..<codebookCount {
                flat[index * codebookCount + channel] = channel < frame.count ? frame[channel] : 0
            }
        }

        let codesTensor = try VieNeuTensor.int32(
            flat,
            shape: [1, NSNumber(value: frames.count), NSNumber(value: codebookCount)]
        )
        let lengthsTensor = try VieNeuTensor.int32([Int32(frames.count)], shape: [1])

        let outputs = try withExtendedLifetime((codesTensor, lengthsTensor)) {
            try codecSession.run(
                withInputs: [
                    "audio_codes": codesTensor.value,
                    "audio_code_lengths": lengthsTensor.value
                ],
                outputNames: outputNames,
                runOptions: nil
            )
        }

        guard let audio = outputs["audio"] else {
            throw TTSError.internalError("Codec không trả output 'audio'")
        }
        let shape = try audio.tensorTypeAndShapeInfo().shape.map(\.intValue)
        let data = try audio.tensorData() as Data
        let totalSamples = data.count / MemoryLayout<Float>.size

        // Codec sinh 48 kHz stereo dạng `(1, 2, N)` — **planar**, không interleaved.
        let channels = shape.count >= 3 ? shape[1] : 1
        let perChannel = channels > 0 ? totalSamples / channels : totalSamples
        guard perChannel > 0 else {
            throw TTSError.internalError("Codec trả 0 mẫu (shape \(shape))")
        }

        var planar = [Float](repeating: 0, count: totalSamples)
        _ = planar.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination, from: 0..<(totalSamples * MemoryLayout<Float>.size))
        }
        guard channels > 1 else { return Array(planar[0..<perChannel]) }

        var mono = [Float](repeating: 0, count: perChannel)
        planar.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return }
            vDSP_vadd(base, 1, base + perChannel, 1, &mono, 1, vDSP_Length(perChannel))
        }
        var half: Float = 0.5
        vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(perChannel))
        return mono
    }

    /// Lọc NaN/Inf rồi chuẩn hoá đỉnh về 0.9.
    ///
    /// Trần khuếch đại 4.0 để một chunk gần như im lặng không bị kéo lên thành tiếng ồn. Model tự
    /// hồi quy đôi khi sinh mẫu không hữu hạn; đưa thẳng vào `AVAudioPlayer` là tiếng nổ.
    func normalise(_ samples: inout [Float]) {
        guard !samples.isEmpty else { return }
        var invalidCount = 0
        var peak: Float = 1e-9
        for index in samples.indices {
            let value = samples[index]
            if !value.isFinite {
                samples[index] = 0
                invalidCount += 1
            } else {
                peak = max(peak, abs(value))
            }
        }
        if invalidCount > 0 {
            AppLogger.shared.log("⚠️ [VieNeu] \(invalidCount) mẫu NaN/Inf bị đưa về 0")
        }
        var gain = min(4.0, 0.9 / peak)
        vDSP_vsmul(samples, 1, &gain, &samples, 1, vDSP_Length(samples.count))
    }

    func appendBoundarySilence(
        _ samples: inout [Float],
        boundaryKind: TTSBoundaryKind,
        sampleRate: Int
    ) {
        let pause = Self.pauseDuration(for: boundaryKind)
        guard pause > 0 else { return }
        let count = Int(Double(sampleRate) * pause)
        guard count > 0 else { return }
        samples.append(contentsOf: [Float](repeating: 0, count: count))
    }

    /// Dùng **đúng** các khoá UserDefaults của đường Piper để hai engine nghỉ giống nhau ở cùng loại
    /// ranh giới — người dùng đã tinh chỉnh các giá trị này cho Piper thì không nên bị reset khi đổi
    /// engine.
    static func pauseDuration(for boundaryKind: TTSBoundaryKind) -> Double {
        let defaults = UserDefaults.standard
        func value(_ key: String, _ fallback: Double) -> Double {
            let stored = defaults.double(forKey: key)
            return stored > 0 ? stored : fallback
        }
        switch boundaryKind {
        case .technicalChunk: return 0
        case .phraseEnd: return value("phrasePauseDuration", 0.15)
        case .bracketEnd: return value("bracketPauseDuration", 0.1)
        case .newlineEnd: return value("newlinePauseDuration", 0.4)
        case .sentenceEnd: return value("sentencePauseDuration", 0.3)
        case .paragraphEnd, .chapterEnd: return value("paragraphPauseDuration", 0.5)
        }
    }

    /// WAV im lặng hợp lệ cho chunk không có gì để đọc.
    ///
    /// Bất biến của repo: chuỗi rỗng phải thành WAV im lặng hợp lệ, không bao giờ đẩy chuỗi rỗng vào
    /// engine và không bao giờ trả payload rỗng cho tầng phát.
    func silence(for boundaryKind: TTSBoundaryKind, sampleRate: Int) -> (data: Data, pcmDuration: Double) {
        let pause = max(0.05, Self.pauseDuration(for: boundaryKind))
        let count = max(1, Int(Double(sampleRate) * pause))
        let samples = [Float](repeating: 0, count: count)
        let wav = WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1)
        return (wav, Double(count) / Double(sampleRate))
    }
}
