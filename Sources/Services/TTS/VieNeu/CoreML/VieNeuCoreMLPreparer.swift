import Foundation

/// Bước **chuẩn bị Core ML** của lượt đo tự động P1b — chạy ngoài MainActor, trước mọi lượt đo:
///
/// 1. **Biên dịch lạnh** từng graph (VE mỗi bucket, codec mỗi bucket), mỗi lần một graph rồi nhả ngay (để RAM không cộng
///    dồn khi chưa biết mỗi session tốn bao nhiêu): ghi ms, RAM lúc giữ session, số partition Core ML (log của ORT).
/// 2. **Nạp ấm** (đọc lại bản biên dịch từ cache): nạp lần lượt, ghi ms + RAM cộng dồn; dừng thêm khi RAM trống còn dưới
///    `minimumHeadroomMB` ⇒ đó là trần số session giữ cùng lúc (`sessionCap`).
/// 3. **Tự kiểm**: mỗi đoạn golden × mọi bucket VE ≥ T × mọi bucket codec ≥ T, so latent / sóng âm với tham chiếu PC (graph
///    gốc). Dưới cổng (rác kiểu tháng 10) ⇒ không chạy lượt Core ML.
enum VieNeuCoreMLPreparer {
    struct Report: Sendable {
        var lines: [String] = []
        var sessionCap = 2
        var passed = false
    }

    /// Cổng tự kiểm: rác (nhiễu như tháng 10) ra quanh 0 dB; fp32 đúng ra > 80 dB.
    static let minimumLatentDB = 40.0
    static let minimumWaveDB = 30.0
    /// RAM trống tối thiểu phải còn sau khi giữ các session Core ML (lượt đọc còn ORT text_encoder + trình phát).
    static let minimumHeadroomMB = 700.0
    /// Ước dung lượng cache biên dịch mỗi bucket (fp32): VE ~153 MB, codec ~99 MB, cộng dư.
    static let veCacheEstimateMB = 170.0
    static let codecCacheEstimateMB = 115.0

    static func requiredCacheMB(_ manifest: VieNeuCoreMLPackage.Manifest) -> Double {
        Double(manifest.veBuckets.count) * veCacheEstimateMB + Double(manifest.codecBuckets.count) * codecCacheEstimateMB
    }

    static func prepare(
        backend: VieNeuCoreMLFlowBackend,
        progress: @Sendable (String) -> Void
    ) throws -> Report {
        let package = backend.package
        let manifest = backend.manifest
        var report = Report()
        try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        let graphs = manifest.veBuckets.sorted().map { ("ve", $0) } + manifest.codecBuckets.sorted().map { ("codec", $0) }

        // 1. Biên dịch lạnh, từng graph một.
        report.lines.append("— Biên dịch Core ML (lần đầu; có bản lưu thì là nạp lại) —")
        backend.setSessionCap(64)
        for (index, (kind, bucket)) in graphs.enumerated() {
            try Task.checkCancellation()
            progress("Biên dịch Core ML \(index + 1)/\(graphs.count): \(kind) T\(bucket)…")
            backend.releaseSessions()
            let before = ProcessMemoryProbe.snapshot()
            let logURL = package.resultsURL.appendingPathComponent("compile-\(kind)\(bucket).log")
            let ms = try backend.loadSession(kind: kind, bucket: bucket, logPath: logURL.path)
            let held = ProcessMemoryProbe.snapshot()
            report.lines.append(String(
                format: "%@ T%ld: %.1f s · RAM +%.0f MB khi giữ session · %@", kind, bucket, ms / 1_000,
                held.footprintMB - before.footprintMB, partitionNote(logURL)
            ))
        }
        backend.releaseSessions()

        // 2. Nạp ấm, cộng dồn, tới khi chạm trần RAM.
        report.lines.append("— Nạp lại từ bản biên dịch (ấm) —")
        let start = ProcessMemoryProbe.snapshot()
        var loaded = 0
        for (kind, bucket) in graphs {
            try Task.checkCancellation()
            progress("Nạp lại \(kind) T\(bucket)…")
            let ms = try backend.loadSession(kind: kind, bucket: bucket)
            let now = ProcessMemoryProbe.snapshot()
            loaded += 1
            report.lines.append(String(format: "%@ T%ld: %.2f s · %@", kind, bucket, ms / 1_000, now.summary))
            if now.availableMB > 0, now.availableMB < minimumHeadroomMB, loaded < graphs.count {
                report.lines.append("⚠️ RAM trống dưới \(Int(minimumHeadroomMB)) MB ⇒ chỉ giữ \(loaded) session cùng lúc")
                break
            }
        }
        report.sessionCap = max(2, loaded)
        backend.setSessionCap(report.sessionCap)
        let end = ProcessMemoryProbe.snapshot()
        report.lines.append(String(
            format: "giữ %ld session: RAM +%.0f MB (từ %@) · trần lúc đọc %ld session · cache %@",
            loaded, end.footprintMB - start.footprintMB, start.summary, report.sessionCap,
            ByteCountFormatter.string(fromByteCount: package.cacheBytes, countStyle: .file)
        ))

        // 3. Tự kiểm mọi bucket với golden.
        report.lines.append("— Tự kiểm (so tham chiếu PC, graph gốc) —")
        report.passed = try selfTest(backend: backend, report: &report, progress: progress)
        backend.resetStats()
        report.lines.append(report.passed
            ? "✅ Core ML qua cổng (latent ≥ \(Int(minimumLatentDB)) dB, sóng âm ≥ \(Int(minimumWaveDB)) dB, không NaN)"
            : "❌ Core ML KHÔNG qua cổng ⇒ bỏ lượt Core ML")
        return report
    }

    private static func selfTest(
        backend: VieNeuCoreMLFlowBackend,
        report: inout Report,
        progress: @Sendable (String) -> Void
    ) throws -> Bool {
        let manifest = backend.manifest
        let golden = try VieNeuNanoGolden(url: backend.package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        let length = Int64(manifest.lengthFrozen)
        let dim = Int64(VieNeuCoreMLFlowBackend.contextDim)
        let styleRows = golden.style.count / VieNeuCoreMLFlowBackend.contextDim
        let grid: [Double] = golden.grid.map { Double($0) }
        let nullMask: [UInt8] = golden.nullCtxMask.map { $0 > 0.5 ? UInt8(1) : UInt8(0) }
        let shape: [Int64] = [1, length, dim]
        var passed = true
        for (index, chunk) in golden.chunks.enumerated() {
            let mask: [UInt8] = chunk.ctxMask.map { $0 > 0.5 ? UInt8(1) : UInt8(0) }
            let request = VieNeuFlowRequest(
                latent: chunk.x0, frames: chunk.frames, latentChannels: VieNeuNanoGolden.channels,
                grid: grid, cfg: VieNeuNanoEPWorker.cfg,
                context: chunk.ctx, contextShape: shape, mask: mask,
                speaker: golden.spk, style: golden.style, styleRows: styleRows,
                styleColumns: VieNeuCoreMLFlowBackend.contextDim,
                nullContext: golden.nullCtx, nullContextShape: shape, nullMask: nullMask,
                nullSpeaker: golden.nullSpk, nullStyle: golden.nullStyle
            )
            for veBucket in manifest.veBuckets.sorted() where veBucket >= chunk.frames {
                try Task.checkCancellation()
                progress("Tự kiểm đoạn \(index + 1)/\(golden.chunks.count) · VE T\(veBucket)…")
                let latent = try backend.trajectory(request, veBucket: veBucket)
                let latentDB = VieNeuNanoEPWorker.snr(chunk.latent, latent)
                var parts = ["latent \(VieNeuNanoEPWorker.format(latentDB))"]
                var nan = latent.contains(where: \.isNaN)
                passed = passed && latentDB >= minimumLatentDB
                for codecBucket in manifest.codecBuckets.sorted() where codecBucket >= chunk.frames {
                    let wave = try backend.decode(
                        latent: latent, frames: chunk.frames, latentChannels: VieNeuNanoGolden.channels,
                        codecBucket: codecBucket
                    )
                    let waveDB = VieNeuNanoEPWorker.snr(chunk.wav, wave)
                    nan = nan || wave.contains(where: \.isNaN)
                    passed = passed && waveDB >= minimumWaveDB
                    parts.append("codec T\(codecBucket) \(VieNeuNanoEPWorker.format(waveDB))")
                }
                passed = passed && !nan
                report.lines.append("đoạn \(index + 1) (T=\(chunk.frames)) VE T\(veBucket): \(parts.joined(separator: " · ")) dB\(nan ? " · NaN!" : "")")
            }
        }
        return passed
    }

    /// "1 partition Core ML" từ log ORT (`number of partitions supported by CoreML: N`).
    private static func partitionNote(_ url: URL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "không đọc được log" }
        let marker = "number of partitions supported by CoreML: "
        let counts = text.components(separatedBy: marker).dropFirst().compactMap { piece in
            Int(piece.prefix { $0.isNumber })
        }
        guard let last = counts.last else { return "đã có bản biên dịch (không dựng lại)" }
        return "\(last) partition Core ML"
    }
}
