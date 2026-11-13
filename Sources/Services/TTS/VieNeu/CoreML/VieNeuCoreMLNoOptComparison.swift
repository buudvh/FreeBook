import Foundation

/// Bước 5 của phép thử P2b-0: cùng đoạn golden chạy qua **bản biên dịch hiện tại** (`Cache/`) và **bản tắt tối ưu ORT**
/// (`Cache-noopt/`), VE + codec bucket nhỏ nhất.
///
/// - Chất lượng: dB so tham chiếu PC (cổng như tự kiểm: latent ≥ 40, sóng âm ≥ 30, không NaN) và dB **giữa hai bản**.
/// - Tốc độ (bắt buộc — nạp nhanh mà mất tốc độ ×2 của Core ML thì vô ích): một lượt khởi động, rồi 2 vòng xen kẽ hai bản,
///   lấy trung vị thời gian mỗi quỹ đạo VE (8 bước × CFG = 16 lượt VE) và mỗi lần codec.
enum VieNeuCoreMLNoOptComparison {
    static func run(
        package: VieNeuCoreMLPackage,
        manifest: VieNeuCoreMLPackage.Manifest,
        progress: (String) -> Void
    ) throws -> (lines: [String], summary: [String]) {
        typealias Worker = VieNeuCoreMLLoadWorker
        guard let ve = manifest.veBuckets.min(), let codec = manifest.codecBuckets.min() else {
            return (["== 5. So bản: manifest không có bucket"], [])
        }
        let limit = min(ve, codec)
        var lines = ["== 5. Chất lượng + tốc độ: bản hiện tại so với bản tắt tối ưu (đoạn golden T ≤ \(limit))"]
        let current = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 4)
        let noOpt = VieNeuCoreMLFlowBackend(package: package, manifest: manifest, sessionCap: 4, disablesGraphOptimization: true)
        defer {
            current.releaseSessions()
            noOpt.releaseSessions()
        }
        for (name, backend) in [("hiện tại", current), ("tắt tối ưu", noOpt)] {
            try Task.checkCancellation()
            progress("Nạp session bản \(name)…")
            let veLoad = try Worker.timed { try backend.loadSession(kind: "ve", bucket: ve) }
            let codecLoad = try Worker.timed { try backend.loadSession(kind: "codec", bucket: codec) }
            lines.append("nạp session bản \(name): VE T\(ve) \(veLoad.text) · codec T\(codec) \(codecLoad.text) · \(Worker.thermal())")
        }

        let golden = try VieNeuNanoGolden(url: package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        let veCalls = max(1, (golden.grid.count - 1) * (VieNeuNanoEPWorker.cfg > 0 ? 2 : 1))
        let channels = VieNeuNanoGolden.channels
        var currentVE: [Double] = []
        var noOptVE: [Double] = []
        var currentCodec: [Double] = []
        var noOptCodec: [Double] = []
        var passed = true
        var minimumBetween = Double.infinity
        for (index, chunk) in golden.chunks.enumerated() where chunk.frames <= limit {
            try Task.checkCancellation()
            progress("So đoạn golden \(index + 1) (T=\(chunk.frames))…")
            let request = VieNeuCoreMLPreparer.goldenRequest(chunk, golden: golden, manifest: manifest)
            // Lượt khởi động (lượt đầu mỗi session chậm hơn) — cũng là lượt lấy dB.
            let latentA = try current.trajectory(request, veBucket: ve)
            let latentB = try noOpt.trajectory(request, veBucket: ve)
            let waveA = try current.decode(latent: latentA, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
            let waveB = try noOpt.decode(latent: latentB, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
            let latentNoOptDB = VieNeuNanoEPWorker.snr(chunk.latent, latentB)
            let waveNoOptDB = VieNeuNanoEPWorker.snr(chunk.wav, waveB)
            let nan = latentB.contains(where: \.isNaN) || waveB.contains(where: \.isNaN)
            passed = passed && !nan && latentNoOptDB >= VieNeuCoreMLPreparer.minimumLatentDB
                && waveNoOptDB >= VieNeuCoreMLPreparer.minimumWaveDB
            let latentBetween = VieNeuNanoEPWorker.snr(latentA, latentB)
            minimumBetween = min(minimumBetween, latentBetween)
            lines.append("đoạn \(index + 1) (T=\(chunk.frames)): latent hiện tại \(format(VieNeuNanoEPWorker.snr(chunk.latent, latentA)))"
                + " · tắt tối ưu \(format(latentNoOptDB)) · giữa hai bản \(format(latentBetween)) dB; sóng âm hiện tại "
                + "\(format(VieNeuNanoEPWorker.snr(chunk.wav, waveA))) · tắt tối ưu \(format(waveNoOptDB))"
                + " · giữa hai bản \(format(VieNeuNanoEPWorker.snr(waveA, waveB))) dB\(nan ? " · NaN!" : "")")

            for _ in 0..<2 {
                try Task.checkCancellation()
                let veCurrent = try Worker.timed { try current.trajectory(request, veBucket: ve) }
                let veNoOpt = try Worker.timed { try noOpt.trajectory(request, veBucket: ve) }
                let codecCurrent = try Worker.timed {
                    try current.decode(latent: latentA, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
                }
                let codecNoOpt = try Worker.timed {
                    try noOpt.decode(latent: latentB, frames: chunk.frames, latentChannels: channels, codecBucket: codec)
                }
                currentVE.append(veCurrent.wallMs)
                noOptVE.append(veNoOpt.wallMs)
                currentCodec.append(codecCurrent.wallMs)
                noOptCodec.append(codecNoOpt.wallMs)
            }
        }
        guard !currentVE.isEmpty else {
            lines.append("không có đoạn golden nào vừa T\(limit) — chưa so được")
            return (lines, ["so bản: không có đoạn golden vừa bucket"])
        }

        let veA = median(currentVE)
        let veB = median(noOptVE)
        let codecA = median(currentCodec)
        let codecB = median(noOptCodec)
        lines.append(String(
            format: "quỹ đạo VE T%ld (%ld lượt VE): hiện tại %.0f ms (%.1f ms/lượt) · tắt tối ưu %.0f ms (%.1f ms/lượt) · "
                + "tắt tối ưu / hiện tại %.2f× · %@",
            ve, veCalls, veA, veA / Double(veCalls), veB, veB / Double(veCalls), veB / max(veA, 0.001), Worker.thermal()
        ))
        lines.append(String(
            format: "codec T%ld: hiện tại %.0f ms · tắt tối ưu %.0f ms · tắt tối ưu / hiện tại %.2f× (trung vị %ld lần đo mỗi bản)",
            codec, codecA, codecB, codecB / max(codecA, 0.001), currentVE.count
        ))
        let verdict = passed ? "qua cổng" : "KHÔNG qua cổng"
        lines.append("⇒ bản tắt tối ưu \(verdict) · lệch nhỏ nhất giữa hai bản (latent) \(format(minimumBetween)) dB")
        let summary = [
            String(format: "tốc độ VE T%ld: hiện tại %.1f ms/lượt · tắt tối ưu %.1f ms/lượt (%.2f×)",
                   ve, veA / Double(veCalls), veB / Double(veCalls), veB / max(veA, 0.001)),
            String(format: "tốc độ codec T%ld: hiện tại %.0f ms · tắt tối ưu %.0f ms (%.2f×)",
                   codec, codecA, codecB, codecB / max(codecA, 0.001)),
            "chất lượng bản tắt tối ưu: \(verdict) · giữa hai bản ≥ \(format(minimumBetween)) dB"
        ]
        return (lines, summary)
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }

    private static func format(_ db: Double) -> String {
        VieNeuNanoEPWorker.format(db)
    }
}
