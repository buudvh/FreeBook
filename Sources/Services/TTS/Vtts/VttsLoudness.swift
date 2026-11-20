import Accelerate
import Foundation

/// Chất tiếng + âm lượng **mỗi đoạn** vtts — "bản 4" anh Bửu chọn bằng tai (1.3.1036; trước đó 1.3.1033 chỉ tăng về
/// −16 dBFS và anh vẫn nghe "không to bằng google tts").
///
/// ## Vì sao không chỉ tăng âm lượng
/// Đo trên CI (1.3.1034, cùng đoạn truyện ~35 s): Google readaloud 6 giọng −19,8 LUFS, vtts 1.3.1033 đã **ngang / to hơn**
/// (nu-10 −19,4, nam-1 −17,8) mà vẫn nghe nhỏ: model dồn ~½ năng lượng ở 80–300 Hz (loa iPhone gần như không phát) và rất
/// ít ở 2–4 kHz (dải tai nhạy nhất). Anh nghe 4 bản dựng sẵn (hiện tại / +4 dB / sáng hơn / sáng + to hơn) và chọn bản 4.
///
/// ## Các bước (đúng thứ tự đã dựng bản anh nghe)
/// 1. **Chỉnh tiếng**: lọc thông cao 150 Hz (Q 0,707) + nâng +6 dB quanh 2,8 kHz (Q 0,9) — biquad RBJ, trạng thái `Double`.
/// 2. **Kéo mức**: RMS trên khung 20 ms **có tiếng** (khung ≤ −45 dBFS bị bỏ) về −14 dBFS (≈ −16 LUFS), chỉ tăng,
///    `0…maxGainDb`. Đoạn có tiếng < 0,4 s ("Ừ.", một cái tên): không đo (dễ đẩy to tiếng thở) — dùng mức cố định theo
///    giọng (`VttsVoice.defaultLoudnessGainDb`).
/// 3. **Ghìm đỉnh** về ≤ −1 dBFS thay cho cách cũ hạ cả đoạn (cách cũ chặn mức to ~−17,5 LUFS, giọng nam-1 đã chạm trần):
///    mức cần của từng mẫu giữ cực tiểu trong ±5 ms, trung bình trượt ±5 ms (hạ trước đỉnh, mượt), nhả theo hàm mũ 80 ms.
///    Tại mỗi đỉnh hệ số ≤ mức cần (mọi mẫu trong cửa sổ trung bình đều đã ≤ mức cần của đỉnh) ⇒ không vượt trần, không để
///    `WAVEncoder` kẹp cứng gây rè.
///
/// Chạy trên mẫu lời đọc **sau** `VttsEdgeFade`, **trước** khi nối khoảng lặng đuôi; áp cho mọi đường qua `VttsTTSService`
/// (trình đọc chính, giọng dự phòng, ▶ thử giọng). Log `🗣️ [Vtts] Đoạn` ghi `gain=` + `limit=`.
enum VttsLoudness {
    struct Result {
        /// Mức đã tăng ở bước 2 (dB, 0 = giữ nguyên).
        let gainDb: Float
        /// Mức ghìm sâu nhất ở bước 3 (dB, ≤ 0; 0 = không ghìm).
        let limitDb: Float

        static let unchanged = Result(gainDb: 0, limitDb: 0)
    }

    static let targetRMSDb: Float = -14
    static let maxGainDb: Float = 18
    static let peakCeilingDb: Float = -1
    static let speechFrameFloorDb: Float = -45
    static let frameSeconds = 0.02
    static let minimumSpeechSeconds = 0.4

    static let lowCutHz = 150.0
    static let lowCutQ = 0.707
    static let presenceHz = 2_800.0
    static let presenceQ = 0.9
    static let presenceGainDb = 6.0

    static let lookaheadSeconds = 0.005
    static let releaseSeconds = 0.08

    /// Sửa `samples` tại chỗ (chỉnh tiếng → kéo mức → ghìm đỉnh); trả số liệu để ghi log.
    @discardableResult
    static func process(_ samples: inout [Float], sampleRate: Int, fallbackGainDb: Float) -> Result {
        guard !samples.isEmpty, sampleRate > 0 else { return .unchanged }
        applyPresenceEQ(&samples, sampleRate: sampleRate)

        let measured = speechRMS(samples, sampleRate: sampleRate)
        var gainDb = measured.map { targetRMSDb - decibels($0) } ?? fallbackGainDb
        gainDb = max(0, min(gainDb, maxGainDb))
        if gainDb >= 0.1 {
            samples = vDSP.multiply(Float(pow(10, Double(gainDb) / 20)), samples)
        } else {
            gainDb = 0
        }
        let limitDb = limitPeaks(&samples, sampleRate: sampleRate)
        return Result(gainDb: gainDb, limitDb: limitDb)
    }

    // MARK: - Bước 1: chỉnh tiếng

    private struct Biquad {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double

        /// Lọc thông cao bậc 2 (RBJ cookbook).
        static func highPass(frequency: Double, q: Double, sampleRate: Int) -> Biquad {
            let omega = 2 * Double.pi * frequency / Double(sampleRate)
            let alpha = sin(omega) / (2 * q)
            let cosine = cos(omega)
            let a0 = 1 + alpha
            return Biquad(
                b0: (1 + cosine) / 2 / a0,
                b1: -(1 + cosine) / a0,
                b2: (1 + cosine) / 2 / a0,
                a1: -2 * cosine / a0,
                a2: (1 - alpha) / a0
            )
        }

        /// Nâng / hạ quanh một tần số (peaking EQ, RBJ cookbook).
        static func peak(frequency: Double, q: Double, gainDb: Double, sampleRate: Int) -> Biquad {
            let amplitude = pow(10, gainDb / 40)
            let omega = 2 * Double.pi * frequency / Double(sampleRate)
            let alpha = sin(omega) / (2 * q)
            let cosine = cos(omega)
            let a0 = 1 + alpha / amplitude
            return Biquad(
                b0: (1 + alpha * amplitude) / a0,
                b1: -2 * cosine / a0,
                b2: (1 - alpha * amplitude) / a0,
                a1: -2 * cosine / a0,
                a2: (1 - alpha / amplitude) / a0
            )
        }

        /// Dạng trực tiếp I, trạng thái bắt đầu từ 0 (đầu đoạn vtts luôn có khoảng lặng).
        func apply(_ samples: inout [Float]) {
            var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0
            for index in samples.indices {
                let input = Double(samples[index])
                let output = b0 * input + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                x2 = x1
                x1 = input
                y2 = y1
                y1 = output
                samples[index] = Float(output)
            }
        }
    }

    private static func applyPresenceEQ(_ samples: inout [Float], sampleRate: Int) {
        // Tần số lọc phải dưới Nyquist — giọng vi-en là 22 050 Hz nên luôn đúng; chặn cho tần số lạ.
        guard Double(sampleRate) / 2 > presenceHz * 1.2 else { return }
        Biquad.highPass(frequency: lowCutHz, q: lowCutQ, sampleRate: sampleRate).apply(&samples)
        Biquad.peak(frequency: presenceHz, q: presenceQ, gainDb: presenceGainDb, sampleRate: sampleRate).apply(&samples)
    }

    // MARK: - Bước 2: đo mức

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

    // MARK: - Bước 3: ghìm đỉnh

    /// Trả mức ghìm sâu nhất (dB, ≤ 0). Không mẫu nào vượt trần ⇒ không đụng gì.
    private static func limitPeaks(_ samples: inout [Float], sampleRate: Int) -> Float {
        let ceiling = Float(pow(10, Double(peakCeilingDb) / 20))
        guard vDSP.maximumMagnitude(samples) > ceiling else { return 0 }
        let count = samples.count
        let reach = max(1, Int(Double(sampleRate) * lookaheadSeconds))

        // Mức cần của mỗi đỉnh phủ ±reach quanh nó (giữ giá trị nhỏ nhất).
        var held = [Float](repeating: 1, count: count)
        for index in 0..<count {
            let magnitude = abs(samples[index])
            guard magnitude > ceiling else { continue }
            let needed = ceiling / magnitude
            for neighbour in max(0, index - reach)...min(count - 1, index + reach) where held[neighbour] > needed {
                held[neighbour] = needed
            }
        }

        // Trung bình trượt cửa sổ [i − reach, i + reach] + nhả theo hàm mũ; hệ số chỉ tụt theo trung bình, lên dần.
        let release = 1 - exp(-1 / (releaseSeconds * Double(sampleRate)))
        var windowSum = 0.0
        var windowCount = 0
        for neighbour in 0...min(reach, count - 1) {
            windowSum += Double(held[neighbour])
            windowCount += 1
        }
        var gain = 1.0
        var deepest = 1.0
        for index in 0..<count {
            gain = min(windowSum / Double(windowCount), gain + (1 - gain) * release)
            samples[index] *= Float(gain)
            deepest = min(deepest, gain)
            let entering = index + reach + 1
            if entering < count {
                windowSum += Double(held[entering])
                windowCount += 1
            }
            let leaving = index - reach
            if leaving >= 0 {
                windowSum -= Double(held[leaving])
                windowCount -= 1
            }
        }
        return Float(20 * log10(max(deepest, 1e-9)))
    }

    private static func decibels(_ amplitude: Float) -> Float {
        Float(20 * log10(Double(max(amplitude, 1e-9))))
    }
}
