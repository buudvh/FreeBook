import Accelerate
import Foundation

/// **Ghìm đỉnh mềm** dùng chung cho tiếng của các trình đọc offline (1.3.1047 — tách từ bước 3 của `VttsLoudness`,
/// 1.3.1036): sau bước kéo âm lượng, mọi mẫu ≤ trần (mặc định −1 dBFS) mà không kẹp cứng.
///
/// Mức cần của từng mẫu vượt trần giữ cực tiểu trong ±5 ms, trung bình trượt ±5 ms (hạ trước đỉnh, mượt), nhả theo hàm mũ
/// 80 ms. Tại mỗi đỉnh hệ số ≤ mức cần (mọi mẫu trong cửa sổ trung bình đều đã ≤ mức cần của đỉnh) ⇒ không vượt trần, không
/// để `WAVEncoder` kẹp cứng gây rè. Không mẫu nào vượt trần ⇒ không đụng gì (tiếng y như trước).
///
/// Người dùng: `VttsLoudness` (vtts), `TTSVolumeStage` (NghiTTS, VieNeu Nano / Turbo).
enum TTSPeakLimiter {
    static let defaultCeilingDb: Float = -1
    static let lookaheadSeconds = 0.005
    static let releaseSeconds = 0.08

    /// Sửa `samples` tại chỗ; trả mức ghìm sâu nhất (dB, ≤ 0; 0 = không ghìm).
    @discardableResult
    static func limit(_ samples: inout [Float], sampleRate: Int, ceilingDb: Float = defaultCeilingDb) -> Float {
        guard !samples.isEmpty, sampleRate > 0 else { return 0 }
        let ceiling = Float(pow(10, Double(ceilingDb) / 20))
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
}
