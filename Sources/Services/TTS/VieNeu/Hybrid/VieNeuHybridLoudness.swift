import Foundation

/// Khớp **âm lượng** khi đọc lai (1.3.934): hai model ra mức to nhỏ khác nhau, và không có lớp nào san giữa chúng
/// (`VieNeuTTSEngine.joinChunks` chỉ khớp các chunk **trong một lượt** Nano, Turbo không khớp gì).
///
/// Cách làm dè dặt như `joinChunks`: nhớ mức RMS trung bình trượt của các đoạn **model chính**, rồi kéo đoạn của **model
/// kia** về mức đó, hệ số kẹp trong [0,6 … 1,6] (±4 dB). Đoạn của model chính **không** bị đụng — nghe y như khi không đọc
/// lai. RMS chỉ tính trên mẫu có tiếng (|x| > ~−50 dB) để khoảng lặng chèn cuối đoạn không kéo mức xuống.
///
/// Chỉ nhận WAV PCM16 mono đúng khuôn 44 byte của `WAVEncoder` (cả hai service đều ra khuôn đó); khác khuôn ⇒ trả nguyên.
final class VieNeuHybridLoudness: @unchecked Sendable {
    private static let headerSize = 44
    private static let silenceFloor: Int32 = 100
    private static let smoothing: Float = 0.2
    private static let minimumGain: Float = 0.6
    private static let maximumGain: Float = 1.6

    private let lock = NSLock()
    private var baseLevel: Float?

    /// Quên mức đã nhớ (đổi giọng / chuẩn bị lại) — giọng khác có mức khác.
    func reset() {
        lock.lock()
        baseLevel = nil
        lock.unlock()
    }

    func match(_ wav: Data, isBaseModel: Bool) -> Data {
        guard Self.isCanonicalPCM16Mono(wav), let level = Self.activeLevel(of: wav) else { return wav }
        lock.lock()
        if isBaseModel {
            baseLevel = baseLevel.map { $0 + Self.smoothing * (level - $0) } ?? level
            lock.unlock()
            return wav
        }
        let target = baseLevel
        lock.unlock()
        guard let target else { return wav }
        let gain = min(Self.maximumGain, max(Self.minimumGain, target / level))
        guard abs(gain - 1) >= 0.05 else { return wav }
        return Self.scaled(wav, by: gain)
    }

    // MARK: - PCM16

    private static func isCanonicalPCM16Mono(_ data: Data) -> Bool {
        data.count > headerSize
            && data[data.startIndex..<data.startIndex + 4].elementsEqual("RIFF".utf8)
            && data[data.startIndex + 8..<data.startIndex + 12].elementsEqual("WAVE".utf8)
            && data[data.startIndex + 36..<data.startIndex + 40].elementsEqual("data".utf8)
            && readUInt16(data, at: 20) == 1
            && readUInt16(data, at: 22) == 1
            && readUInt16(data, at: 34) == 16
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    /// RMS (thang 0…1) của các mẫu có tiếng; `nil` khi gần như im lặng.
    private static func activeLevel(of data: Data) -> Float? {
        var sum: Double = 0
        var count = 0
        data.withUnsafeBytes { raw in
            for offset in stride(from: headerSize, to: raw.count - 1, by: 2) {
                let value = Int32(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)))
                guard abs(value) > silenceFloor else { continue }
                sum += Double(value) * Double(value)
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return Float((sum / Double(count)).squareRoot() / 32768)
    }

    private static func scaled(_ data: Data, by gain: Float) -> Data {
        var output = data
        output.withUnsafeMutableBytes { raw in
            for offset in stride(from: headerSize, to: raw.count - 1, by: 2) {
                let sample = Int16(littleEndian: raw.loadUnaligned(fromByteOffset: offset, as: Int16.self))
                let value = Float(sample) * gain
                let clamped = Int16(max(-32768, min(32767, value.rounded())))
                raw.storeBytes(of: clamped.littleEndian, toByteOffset: offset, as: Int16.self)
            }
        }
        return output
    }
}
