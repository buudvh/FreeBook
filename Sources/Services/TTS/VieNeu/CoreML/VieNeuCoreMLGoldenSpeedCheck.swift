import Foundation

/// Phần "chất lượng + tốc độ" của phép đo P2b-1: cùng đoạn golden (T ≤ bucket nhỏ nhất) chạy qua bản biên dịch của gói
/// định dạng 3.
///
/// - **Chất lượng**: dB so tham chiếu PC phải ra **đúng** số của bản định dạng 2 đo trên máy (1.3.912 / 1.3.913: latent
///   102,5 / 106,3; sóng âm 85,7 / 101,4). Gemm `transB=1` chỉ đổi chỗ cất trọng số, op `linear` và giá trị trọng số y
///   hệt ⇒ phép tính Core ML không đổi.
/// - **Tốc độ**: một lượt khởi động rồi 3 vòng; trung vị thời gian mỗi quỹ đạo VE (8 bước × CFG = 16 lượt VE) và mỗi lần
///   codec, so với số đã đo của bản định dạng 2 (VE 42,4 ms/lượt, codec 99 ms — máy "nóng"). Trong ±10% là như cũ (nhiễu
///   đo lúc máy nóng ~8%).
enum VieNeuCoreMLGoldenSpeedCheck {
    /// dB đo trên máy với bản định dạng 2, theo chỉ số đoạn golden (0-based).
    static let referenceLatentDB: [Int: Double] = [1: 102.5, 4: 106.3]
    static let referenceWaveDB: [Int: Double] = [1: 85.7, 4: 101.4]
    static let referenceVEMsPerCall = 42.4
    static let referenceCodecMs = 99.0
    static let speedTolerance = 0.10

    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: [String]) {
        typealias Worker = VieNeuCoreMLLoadWorker
        guard let ve = manifest.veBuckets.min(), let codec = manifest.codecBuckets.min() else {
            return (["== 5. Chất lượng + tốc độ: manifest không có bucket"], [])
        }
        let limit = min(ve, codec)
        var lines = ["== 5. Chất lượng + tốc độ (đoạn golden T ≤ \(limit), VE T\(ve), codec T\(codec))"]
        let backend = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 4)
        defer { backend.releaseSessions() }
        progress("Nạp session để chạy golden…")
        let veLoad = try Worker.timed { try backend.loadSession(kind: "ve", bucket: ve) }
        let codecLoad = try Worker.timed { try backend.loadSession(kind: "codec", bucket: codec) }
        lines.append("nạp session: VE T\(ve) \(veLoad.text) · codec T\(codec) \(codecLoad.text) · \(Worker.thermal())")

        let golden = try VieNeuNanoGolden(url: package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        let veCalls = max(1, (golden.grid.count - 1) * (VieNeuNanoEPWorker.cfg > 0 ? 2 : 1))
        let channels = VieNeuNanoGolden.channels
        var veTimes: [Double] = []
        var codecTimes: [Double] = []
        var passed = true
        var matchesReference = true
        for (index, chunk) in golden.chunks.enumerated() where chunk.frames <= limit {
            try Task.checkCancellation()
            progress("Chạy đoạn golden \(index + 1) (T=\(chunk.frames))…")
            let request = VieNeuCoreMLPreparer.goldenRequest(chunk, golden: golden, manifest: manifest)
            let latent = try backend.trajectory(request, veBucket: ve) // cũng là lượt khởi động
            let wave = try backend.decode(latent: latent, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
            let latentDB = VieNeuNanoEPWorker.snr(chunk.latent, latent)
            let waveDB = VieNeuNanoEPWorker.snr(chunk.wav, wave)
            let nan = latent.contains(where: \.isNaN) || wave.contains(where: \.isNaN)
            passed = passed && !nan && latentDB >= VieNeuCoreMLPreparer.minimumLatentDB
                && waveDB >= VieNeuCoreMLPreparer.minimumWaveDB
            let same = matches(latentDB, referenceLatentDB[index]) && matches(waveDB, referenceWaveDB[index])
            matchesReference = matchesReference && same
            lines.append("đoạn \(index + 1) (T=\(chunk.frames)): latent \(VieNeuNanoEPWorker.format(latentDB))"
                + "\(referenceText(referenceLatentDB[index])) · sóng âm \(VieNeuNanoEPWorker.format(waveDB))"
                + "\(referenceText(referenceWaveDB[index])) dB\(nan ? " · NaN!" : "")\(same ? " · trùng số cũ" : " · KHÁC số cũ")")

            for _ in 0..<3 {
                try Task.checkCancellation()
                let veRun = try Worker.timed { try backend.trajectory(request, veBucket: ve) }
                let codecRun = try Worker.timed {
                    try backend.decode(latent: latent, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
                }
                veTimes.append(veRun.wallMs)
                codecTimes.append(codecRun.wallMs)
            }
        }
        guard !veTimes.isEmpty else {
            lines.append("không có đoạn golden nào vừa T\(limit) — chưa đo được")
            return (lines, ["chất lượng + tốc độ: không có đoạn golden vừa bucket"])
        }

        let vePerCall = median(veTimes) / Double(veCalls)
        let codecMs = median(codecTimes)
        let veRatio = vePerCall / referenceVEMsPerCall
        let codecRatio = codecMs / referenceCodecMs
        lines.append(String(
            format: "VE T%ld: %.1f ms/lượt (quỹ đạo %ld lượt %.0f ms) · bản cũ %.1f ms/lượt ⇒ %.2f× (%@) · %@",
            ve, vePerCall, veCalls, median(veTimes), referenceVEMsPerCall, veRatio, speedWord(veRatio), Worker.thermal()
        ))
        lines.append(String(
            format: "codec T%ld: %.0f ms · bản cũ %.0f ms ⇒ %.2f× (%@) · trung vị %ld lần đo",
            codec, codecMs, referenceCodecMs, codecRatio, speedWord(codecRatio), veTimes.count
        ))
        let quality = passed ? (matchesReference ? "qua cổng, trùng số cũ" : "qua cổng nhưng KHÁC số cũ") : "KHÔNG qua cổng"
        lines.append("⇒ chất lượng: \(quality)")
        let summary = [
            "chất lượng: \(quality)",
            String(format: "tốc độ VE T%ld: %.1f ms/lượt (cũ %.1f) ⇒ %.2f× %@", ve, vePerCall, referenceVEMsPerCall, veRatio,
                   speedWord(veRatio)),
            String(format: "tốc độ codec T%ld: %.0f ms (cũ %.0f) ⇒ %.2f× %@", codec, codecMs, referenceCodecMs, codecRatio,
                   speedWord(codecRatio))
        ]
        return (lines, summary)
    }

    private static func matches(_ value: Double, _ reference: Double?) -> Bool {
        guard let reference else { return true }
        return abs(value - reference) <= 0.06
    }

    private static func referenceText(_ reference: Double?) -> String {
        reference.map { String(format: " (cũ %.1f)", $0) } ?? ""
    }

    private static func speedWord(_ ratio: Double) -> String {
        if ratio > 1 + speedTolerance { return "CHẬM HƠN" }
        if ratio < 1 - speedTolerance { return "nhanh hơn" }
        return "như cũ"
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
