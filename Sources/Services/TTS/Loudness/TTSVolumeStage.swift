import Accelerate
import Foundation

/// Bước **âm lượng theo giọng** cuối mỗi đoạn của NghiTTS và VieNeu (1.3.1047): nhân số dB của `TTSVolumeSettings` rồi ghìm
/// đỉnh mềm (`TTSPeakLimiter`). vtts không qua đây — `VttsLoudness` đổi mức đích của chính nó.
enum TTSVolumeStage {
    /// Mẫu float (trước khi ghi WAV). **Luôn** ghìm đỉnh, kể cả 0 dB: VieNeu Nano cân các mảnh ±4 dB (`joinChunks`) có thể
    /// đẩy đỉnh quá 0 dBFS ⇒ trước 1.3.1047 `WAVEncoder` kẹp cứng (rè lẹt xẹt). Trả mức ghìm sâu nhất (dB, ≤ 0).
    @discardableResult
    static func apply(_ samples: inout [Float], sampleRate: Int, offsetDb: Int) -> Float {
        if offsetDb != 0, !samples.isEmpty {
            samples = vDSP.multiply(Float(pow(10, Double(offsetDb) / 20)), samples)
        }
        return TTSPeakLimiter.limit(&samples, sampleRate: sampleRate)
    }

    /// WAV PCM16 mono đúng khuôn 44 byte của `WAVEncoder`. 0 dB ⇒ trả nguyên (đã là PCM16 thì không còn mẫu vượt 0 dBFS để
    /// ghìm — NghiTTS tự đẩy đỉnh từng mảnh về 0,9); khác khuôn ⇒ trả nguyên.
    static func applyToWAV(_ data: Data, offsetDb: Int) -> Data {
        guard offsetDb != 0, let sampleRate = canonicalSampleRate(of: data) else { return data }
        var samples = [Float]()
        samples.reserveCapacity((data.count - headerSize) / 2)
        data.withUnsafeBytes { raw in
            for offset in stride(from: headerSize, to: raw.count - 1, by: 2) {
                let value = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                samples.append(Float(value) / 32768)
            }
        }
        apply(&samples, sampleRate: sampleRate, offsetDb: offsetDb)
        return WAVEncoder.encodePCM16(samples: samples, sampleRate: sampleRate, channels: 1)
    }

    private static let headerSize = 44

    /// Tần số mẫu khi `data` là WAV PCM16 mono khuôn `WAVEncoder`; không thì `nil`.
    private static func canonicalSampleRate(of data: Data) -> Int? {
        guard data.count > headerSize,
              data[data.startIndex..<data.startIndex + 4].elementsEqual("RIFF".utf8),
              data[data.startIndex + 8..<data.startIndex + 12].elementsEqual("WAVE".utf8),
              data[data.startIndex + 36..<data.startIndex + 40].elementsEqual("data".utf8),
              uint(data, at: 20, bytes: 2) == 1, uint(data, at: 22, bytes: 2) == 1, uint(data, at: 34, bytes: 2) == 16
        else { return nil }
        let rate = uint(data, at: 24, bytes: 4)
        return rate > 0 ? rate : nil
    }

    private static func uint(_ data: Data, at offset: Int, bytes: Int) -> Int {
        (0..<bytes).reduce(0) { value, index in value | Int(data[data.startIndex + offset + index]) << (8 * index) }
    }
}
