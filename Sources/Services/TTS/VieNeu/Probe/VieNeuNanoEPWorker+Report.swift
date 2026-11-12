import Foundation

/// Tiện ích số học + định dạng báo cáo của `VieNeuNanoEPWorker` (tách file cho gọn).
extension VieNeuNanoEPWorker {
    // MARK: - Mảng [1, 144, T] ↔ [1, 144, bucket]

    static func pad(_ values: [Float], frames: Int, bucket: Int) -> [Float] {
        let channels = VieNeuNanoGolden.channels
        var padded = [Float](repeating: 0, count: channels * bucket)
        for channel in 0..<channels {
            for frame in 0..<min(frames, bucket) {
                padded[channel * bucket + frame] = values[channel * frames + frame]
            }
        }
        return padded
    }

    static func crop(_ values: [Float], frames: Int, bucket: Int) -> [Float] {
        let channels = VieNeuNanoGolden.channels
        var cropped = [Float](repeating: 0, count: channels * frames)
        for channel in 0..<channels {
            for frame in 0..<min(frames, bucket) {
                cropped[channel * frames + frame] = values[channel * bucket + frame]
            }
        }
        return cropped
    }

    // MARK: - Số đo

    /// SNR (dB) của `test` so với `reference`; trùng hẳn ⇒ +∞, có NaN ⇒ −∞.
    static func snr(_ reference: [Float], _ test: [Float]) -> Double {
        let count = min(reference.count, test.count)
        guard count > 0 else { return -.infinity }
        var signal = 0.0
        var error = 0.0
        for index in 0..<count {
            let value = Double(reference[index])
            let delta = value - Double(test[index])
            signal += value * value
            error += delta * delta
        }
        if error.isNaN { return -.infinity }
        return error == 0 ? .infinity : 10 * log10(signal / error)
    }

    static func format(_ db: Double) -> String {
        if db == .infinity { return "∞" }
        if db == -.infinity { return "−∞" }
        return String(format: "%.1f", db)
    }

    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }

    /// 5 đoạn nối nhau, cách 0,25 s — để nghe so cấu hình với tham chiếu.
    static func joinedWav(_ outputs: [ChunkOutput]) -> [Float] {
        let gap = [Float](repeating: 0, count: 6_000)
        var samples: [Float] = []
        for output in outputs {
            samples.append(contentsOf: output.wav)
            samples.append(contentsOf: gap)
        }
        return samples
    }

    /// Lọc log ORT (stderr lúc tạo session) lấy dòng nói về partition / chỗ chạy op — chỉ là chẩn đoán.
    static func logExcerpt(_ url: URL, label: String) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty else {
            return ["[\(label)] không lấy được log của ORT"]
        }
        let lines = text.split(whereSeparator: \.isNewline).map(String.init)
        let keywords = ["CoreML", "partition", "number of nodes", "XNNPACK", "ComputePlan", "NeuralEngine", "GPU", "fallback"]
        let relevant = lines.filter { line in keywords.contains { line.contains($0) } }
        let devices = ["NeuralEngine", "GPU", "CPU"].map { name in "\(name) \(lines.filter { $0.contains(name) }.count)" }
        var excerpt = ["[\(label)] \(lines.count) dòng log, nhắc tới thiết bị: \(devices.joined(separator: " · "))"]
        excerpt += relevant.prefix(12).map { "  " + String($0.prefix(220)) }
        return excerpt
    }

    // MARK: - Báo cáo

    static func report(
        results: [ConfigResult],
        gemm: [VieNeuGEMMBench.Result],
        golden: VieNeuNanoGolden,
        skippedByGate: Bool
    ) -> String {
        var lines = [
            "Phép thử P1 — So EP cho Nano: 5 đoạn golden, quỹ đạo 8 bước + CFG 3, bucket T128, L = 200",
            String(format: "Tổng tiếng: %.2f s · tham chiếu SNR: cấu hình CPU so với PC, các cấu hình khác so với CPU trên máy",
                   golden.audioSeconds),
            ""
        ]
        if skippedByGate {
            lines.append("⚠️ Core ML CPU-only không qua cổng (v bước 0 < \(Int(coreMLCPUGateDB)) dB / NaN / lỗi) ⇒ bỏ qua GPU + ANE.")
            lines.append("")
        }
        for result in results {
            lines.append("== \(result.config.title)")
            lines.append("trạng thái   \(result.status)")
            lines.append("RAM trước    \(result.memoryBefore)")
            if !result.createMs.isEmpty {
                let created = result.createMs.sorted { $0.key < $1.key }
                    .map { "\($0.key) \(String(format: "%.0f", $0.value)) ms" }.joined(separator: " · ")
                lines.append("dựng session \(created)")
            }
            if result.completed {
                let veCPU = result.veCpuMs.reduce(0, +) / 1_000
                let codecCPU = result.codecCpuMs.reduce(0, +) / 1_000
                lines.append(String(format: "VE / lượt   %.1f ms · CPU %.1f ms (trung vị, %ld lượt)",
                                    median(result.veMs), median(result.veCpuMs), result.veMs.count))
                lines.append(String(format: "codec/lượt  %.1f ms · CPU %.1f ms (trung vị)",
                                    median(result.codecMs), median(result.codecCpuMs)))
                lines.append(String(format: "CPU-s/giây tiếng  VE %.3f · codec %.3f · tổng %.3f",
                                    veCPU / golden.audioSeconds, codecCPU / golden.audioSeconds,
                                    (veCPU + codecCPU) / golden.audioSeconds))
                lines.append("SNR v0       \(result.snrV0.map(format).joined(separator: " / ")) dB")
                lines.append("SNR latent   \(result.snrLatent.map(format).joined(separator: " / ")) dB")
                lines.append("SNR sóng âm  \(result.snrWav.map(format).joined(separator: " / ")) dB")
                lines.append("NaN          \(result.nanCount)")
            }
            if !result.h1.isEmpty {
                lines.append("H1 (main T234 / T256, trọng số external data):")
                lines += result.h1.map { "  " + $0 }
            }
            if !result.logExcerpt.isEmpty {
                lines.append("log ORT:")
                lines += result.logExcerpt.map { "  " + $0 }
            }
            lines.append("")
        }
        lines.append("== Accelerate cblas_sgemm (kiểm AMX, fp32)")
        lines += gemm.map(\.line)
        lines.append("(ORT/NEON trong trình đọc ≈ 37 GFLOPS mỗi giây-lõi — cao hơn hẳn ⇒ AMX có thật)")
        return lines.joined(separator: "\n")
    }
}
