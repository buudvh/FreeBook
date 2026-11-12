import Foundation

/// Cả lượt của phép thử P1: CPU (tham chiếu trên máy) → Core ML CPU-only → (qua cổng) GPU, ANE → XNNPACK →
/// Accelerate `cblas_sgemm`. Chạy trong `Task.detached`; hủy task là dừng giữa hai lượt chạy session.
extension VieNeuNanoEPWorker {
    struct Outcome: Sendable {
        let report: String
        let summary: [String]
        let wavURLs: [URL]
    }

    static func runAll(
        package: VieNeuNanoStaticPackage,
        manifest: VieNeuNanoStaticPackage.Manifest,
        progress: @escaping @Sendable (String) -> Void
    ) throws -> Outcome {
        progress("Đọc golden…")
        let golden = try VieNeuNanoGolden(url: package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        var results: [ConfigResult] = []
        var baseline: [ChunkOutput]?
        var skippedByGate = false
        for config in configs {
            try Task.checkCancellation()
            if skippedByGate, config.isCoreML {
                var skipped = ConfigResult(config: config)
                skipped.status = "bỏ qua — Core ML CPU-only không qua cổng"
                results.append(skipped)
                continue
            }
            let (result, outputs) = try run(
                config: config, package: package, manifest: manifest, golden: golden,
                baseline: config.id == "cpu" ? nil : baseline, progress: progress
            )
            results.append(result)
            AppLogger.shared.log("🎙️ [VieNeuProbe] \(summaryLine(result, golden: golden))")
            if config.id == "cpu" {
                guard result.completed else { break } // không có tham chiếu trên máy thì các cấu hình sau vô nghĩa
                baseline = outputs
            }
            if config.id == "coreml-cpu", !passesCoreMLGate(result) { skippedByGate = true }
        }
        try Task.checkCancellation()
        progress("Đo Accelerate cblas_sgemm…")
        let gemm = VieNeuGEMMBench.run()
        let wavURLs = writeWavs(results, golden: golden, package: package)
        let text = report(results: results, gemm: gemm, golden: golden, skippedByGate: skippedByGate)
        AppLogger.shared.log("🎙️ [VieNeuProbe] Xong So EP: \(results.count) cấu hình, \(wavURLs.count) WAV")
        return Outcome(report: text, summary: results.map { summaryLine($0, golden: golden) } + gemm.map(\.line),
                       wavURLs: wavURLs)
    }

    /// Một dòng gọn cho màn hình: trạng thái + ms / CPU-ms trung vị + SNR thấp nhất + NaN.
    static func summaryLine(_ result: ConfigResult, golden: VieNeuNanoGolden) -> String {
        guard result.completed else { return "\(result.config.title): \(result.status)" }
        let cpuSeconds = (result.veCpuMs.reduce(0, +) + result.codecCpuMs.reduce(0, +)) / 1_000
        return String(
            format: "%@: VE %.0f ms (CPU %.0f) · codec %.0f ms · CPU-s/giây tiếng %.3f · SNR v0 ≥ %@ · latent ≥ %@ · sóng âm ≥ %@ dB · NaN %ld",
            result.config.title,
            median(result.veMs), median(result.veCpuMs), median(result.codecMs),
            cpuSeconds / max(0.001, golden.audioSeconds),
            format(result.snrV0.min() ?? -.infinity),
            format(result.snrLatent.min() ?? -.infinity),
            format(result.snrWav.min() ?? -.infinity),
            result.nanCount
        )
    }

    /// WAV để nghe: tham chiếu PC + từng cấu hình chạy xong (5 đoạn nối nhau). Ghi ở `Static/Results/`.
    static func writeWavs(_ results: [ConfigResult], golden: VieNeuNanoGolden, package: VieNeuNanoStaticPackage) -> [URL] {
        try? FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        let reference = joinedWav(golden.chunks.map { ChunkOutput(v0: [], latent: [], wav: $0.wav) })
        var items: [(String, [Float])] = [("nano-pc-tham-chieu", reference)]
        items += results.filter { $0.completed && !$0.wav.isEmpty }.map { ("nano-\($0.config.id)", $0.wav) }
        return items.compactMap { item in
            let (name, samples) = item
            let url = package.resultsURL.appendingPathComponent("\(name).wav")
            let data = WAVEncoder.encodePCM16(samples: samples, sampleRate: 24_000, channels: 1)
            return (try? data.write(to: url, options: .atomic)) != nil ? url : nil
        }
    }
}
