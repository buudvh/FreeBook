import Accelerate
import Foundation

/// Kéo âm lượng **mỗi đoạn** vtts về mức nghe bình thường (1.3.1033, anh Bửu: "giọng nhỏ quá").
///
/// Đo trên WAV đọc thử của CI (câu Việt + Anh 4,5 s): `nu-10` đỉnh −11,3 dBFS, RMS lúc có tiếng −24,1 dBFS; `nam-1`
/// −5,9 / −19,8 dBFS — nhỏ hơn mức TTS thường (~−16…−18 dBFS) khoảng 6–8 dB và 2–4 dB. Mốc −16 dBFS là **ước lượng**
/// mức TTS thường, chưa đo so với VieNeu / Piper / Google; dòng log `🗣️ [Vtts] Đoạn` ghi `gain=` để chỉnh lại theo máy thật.
///
/// - Đo RMS chỉ trên khung 20 ms **có tiếng** (khung ≤ −45 dBFS bị bỏ) ⇒ khoảng lặng giữa câu không kéo mức đo xuống.
/// - Chỉ tăng, trong `0…maxGainDb`; giới hạn để đỉnh sau khi tăng ≤ −1 dBFS — không để `WAVEncoder` kẹp cứng gây rè.
/// - Đoạn có tiếng < 0,4 s ("Ừ.", một cái tên): không đo (dễ đẩy to tiếng thở / tạp âm) — dùng mức cố định theo giọng
///   (`VttsVoice.defaultLoudnessGainDb`), vẫn chịu giới hạn đỉnh.
/// - Chạy trên mẫu lời đọc **trước** khi nối khoảng lặng đuôi; áp cho mọi đường qua `VttsTTSService` (trình đọc chính,
///   giọng dự phòng, ▶ thử giọng).
enum VttsLoudness {
    static let targetRMSDb: Float = -16
    static let maxGainDb: Float = 12
    static let peakCeilingDb: Float = -1
    static let speechFrameFloorDb: Float = -45
    static let frameSeconds = 0.02
    static let minimumSpeechSeconds = 0.4

    /// Nhân `samples` tại chỗ; trả mức đã tăng (dB, 0 = giữ nguyên) để ghi log.
    @discardableResult
    static func normalize(_ samples: inout [Float], sampleRate: Int, fallbackGainDb: Float) -> Float {
        guard !samples.isEmpty, sampleRate > 0 else { return 0 }
        let peak = vDSP.maximumMagnitude(samples)
        guard peak > 0 else { return 0 }

        let measured = speechRMS(samples, sampleRate: sampleRate)
        var gainDb = measured.map { targetRMSDb - decibels($0) } ?? fallbackGainDb
        gainDb = min(gainDb, peakCeilingDb - decibels(peak), maxGainDb)
        gainDb = max(0, gainDb)
        guard gainDb >= 0.1 else { return 0 }

        samples = vDSP.multiply(Float(pow(10, Double(gainDb) / 20)), samples)
        return gainDb
    }

    /// RMS của các khung có tiếng; `nil` khi tổng thời lượng có tiếng ngắn hơn `minimumSpeechSeconds`.
    private static func speechRMS(_ samples: [Float], sampleRate: Int) -> Float? {
        let frame = max(1, Int(Double(sampleRate) * frameSeconds))
        let floorEnergy = Float(pow(10, Double(speechFrameFloorDb) / 10)) * Float(frame)
        var energy: Float = 0
        var speechCount = 0
        var start = 0
        while start + frame <= samples.count {
            let frameEnergy = vDSP.sumOfSquares(samples[start..<(start + frame)])
            if frameEnergy > floorEnergy {
                energy += frameEnergy
                speechCount += frame
            }
            start += frame
        }
        guard speechCount > 0, Double(speechCount) / Double(sampleRate) >= minimumSpeechSeconds else { return nil }
        return (energy / Float(speechCount)).squareRoot()
    }

    private static func decibels(_ amplitude: Float) -> Float {
        Float(20 * log10(Double(max(amplitude, 1e-9))))
    }
}
