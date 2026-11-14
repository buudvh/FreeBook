import Foundation

/// Cắt **mẫu giọng dài** cho nhân bản VieNeu (1.3.936) — thay cho việc báo lỗi "mẫu quá dài" (Nano) và cắt cứng đúng
/// 8,000 s (Turbo). Model chỉ dùng phần đầu mẫu (Nano: x-vector 30 s đầu, style 5 s đầu — `VieNeuVoiceCloner`; Turbo:
/// audio.cpp tự cắt 8 s — `VieNeuTurboReferencePreparer`), nên phần thừa bỏ đi, nhưng **cắt ở chỗ ngắt hơi** gần mốc để
/// không đứt giữa chữ.
///
/// Cách chọn điểm cắt: năng lượng khung 20 ms (bước 10 ms, tổng tiền tố bình phương như `VieNeuSilenceTrimmer`) trong
/// cửa sổ `[mốc − cửa sổ, mốc]`; lấy khung lặng nhất, nhưng ưu tiên khung **muộn nhất** chỉ ồn hơn khung đó tối đa
/// `toleranceDecibels` — giữ được nhiều mẫu nhất. Cắt ở giữa khung, làm nhỏ dần 10 ms cuối để khỏi tiếng "bụp". Mẫu
/// không dài hơn mốc thì giữ nguyên, không đụng một mẫu nào.
enum VieNeuCloneSampleCutter {
    struct Cut: Sendable {
        /// Số mẫu giữ lại (từ đầu mảng).
        let keptCount: Int
        /// Năng lượng khung chọn làm điểm cắt (dBFS).
        let quietDecibels: Double
    }

    /// File mẫu Nano đã cắt (WAV 16-bit mono, thư mục tạm).
    struct NanoSample: Sendable {
        let url: URL
        let originalSeconds: Double
        let keptSeconds: Double
    }

    static let frameSeconds = 0.02
    static let hopSeconds = 0.01
    static let fadeSeconds = 0.01
    static let toleranceDecibels = 3.0

    /// Mốc cắt mẫu Nano — chừa 0,5 s dưới `VieNeuVoiceCloner.maximumSampleSeconds` (30 s, `_MAX_REF_SECONDS` upstream).
    static let nanoCutSeconds = 29.5
    /// Tìm chỗ ngắt hơi trong 3 giây trước mốc (26,5–29,5 s).
    static let nanoSearchSeconds = 3.0

    // MARK: - Cắt mảng

    /// Điểm cắt khi `samples` dài hơn `maxSeconds`; `nil` = không cần cắt.
    static func cut(samples: [Float], sampleRate: Double, maxSeconds: Double, windowSeconds: Double) -> Cut? {
        guard sampleRate > 0 else { return nil }
        let limit = Int((maxSeconds * sampleRate).rounded(.down))
        guard limit > 0, samples.count > limit else { return nil }
        let frame = max(1, Int((frameSeconds * sampleRate).rounded()))
        let hop = max(1, Int((hopSeconds * sampleRate).rounded()))
        let windowStart = max(0, limit - Int((windowSeconds * sampleRate).rounded()))

        var prefix = [Double](repeating: 0, count: limit - windowStart + 1)
        for index in windowStart..<limit {
            let value = Double(samples[index])
            prefix[index - windowStart + 1] = prefix[index - windowStart] + value * value
        }
        var candidates: [(center: Int, decibels: Double)] = []
        var start = windowStart
        while start + frame <= limit {
            let power = (prefix[start + frame - windowStart] - prefix[start - windowStart]) / Double(frame)
            candidates.append((start + frame / 2, 10 * log10(max(1e-12, power))))
            start += hop
        }
        guard let quietest = candidates.map({ $0.decibels }).min(),
              let chosen = candidates.last(where: { $0.decibels <= quietest + toleranceDecibels }) else {
            return Cut(keptCount: limit, quietDecibels: 0)
        }
        return Cut(keptCount: max(1, chosen.center), quietDecibels: chosen.decibels)
    }

    /// Mảng đã cắt (kèm làm nhỏ dần đuôi) + điểm cắt; không cần cắt thì trả nguyên mảng và `nil`.
    static func trimmed(
        _ samples: [Float],
        sampleRate: Double,
        maxSeconds: Double,
        windowSeconds: Double
    ) -> (samples: [Float], cut: Cut?) {
        guard let cut = cut(samples: samples, sampleRate: sampleRate, maxSeconds: maxSeconds, windowSeconds: windowSeconds) else {
            return (samples, nil)
        }
        var kept = Array(samples.prefix(cut.keptCount))
        let fadeCount = min(kept.count, max(1, Int((fadeSeconds * sampleRate).rounded())))
        for step in 0..<fadeCount {
            kept[kept.count - fadeCount + step] *= Float(fadeCount - 1 - step) / Float(fadeCount)
        }
        return (kept, cut)
    }

    // MARK: - File mẫu Nano

    /// Mẫu dài hơn `VieNeuVoiceCloner.maximumSampleSeconds` ⇒ đọc 30 s đầu, cắt ở chỗ ngắt hơi gần 29,5 s, ghi WAV 16-bit mono
    /// (tần số gốc) vào thư mục tạm. `nil` = không cần cắt (dùng nguyên file). Nặng và đồng bộ ⇒ gọi ngoài main.
    ///
    /// Chỉ đọc phần đầu file: một file dài hàng giờ không bị giải mã hết vào RAM, và kho Nano chỉ chép bản đã cắt.
    static func cutForNano(url: URL, durationSeconds: Double) throws -> NanoSample? {
        let maximum = VieNeuVoiceCloner.maximumSampleSeconds
        guard durationSeconds > maximum else { return nil }
        let decoded = try VieNeuAudioResampler.loadMono(url: url, maxSeconds: maximum)
        let result = trimmed(
            decoded.samples,
            sampleRate: decoded.sampleRate,
            maxSeconds: nanoCutSeconds,
            windowSeconds: nanoSearchSeconds
        )
        guard result.cut != nil else { return nil }
        let data = WAVEncoder.encodePCM16(samples: result.samples, sampleRate: Int(decoded.sampleRate.rounded()), channels: 1)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-sample-cut-\(UUID().uuidString).wav")
        try data.write(to: output, options: .atomic)
        let kept = Double(result.samples.count) / decoded.sampleRate
        AppLogger.shared.log(
            "✂️ [VieNeuClone] Mẫu \(format(durationSeconds)) s > \(format(maximum)) s ⇒ Nano giữ \(format(kept)) s đầu " +
            "(chỗ lặng \(String(format: "%.0f", result.cut?.quietDecibels ?? 0)) dB, tìm " +
            "\(format(nanoCutSeconds - nanoSearchSeconds))–\(format(nanoCutSeconds)) s)"
        )
        return NanoSample(url: output, originalSeconds: durationSeconds, keptSeconds: kept)
    }

    static func format(_ seconds: Double) -> String {
        String(format: "%.2f", seconds)
    }
}
