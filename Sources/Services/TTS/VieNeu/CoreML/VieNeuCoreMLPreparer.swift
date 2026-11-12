import Foundation

/// Bước **chuẩn bị Core ML** của lượt đo tự động P1b — chạy ngoài MainActor, trước mọi lượt đo:
///
/// 1. **Biên dịch lạnh** từng graph (VE mỗi bucket, codec mỗi bucket), mỗi lần một graph rồi nhả ngay (để RAM không cộng
///    dồn khi chưa biết mỗi session tốn bao nhiêu): ghi ms, RAM lúc giữ session, số partition Core ML (log của ORT).
/// 2. **Nạp ấm** (đọc lại bản biên dịch từ cache): cũng **từng session một rồi nhả** (1.3.906 — bản 1.3.890 nạp cộng dồn
///    tới 7 session, nghi làm iOS giết app vì hết RAM), ghi ms + RAM khi giữ. Trần số session giữ cùng lúc lúc đọc
///    (`sessionCap`) tính từ RAM trống còn lại và RAM lớn nhất một session đo được (`sessionEstimateMB`).
/// 3. **Tự kiểm**: mỗi đoạn golden × mọi bucket VE ≥ T × mọi bucket codec ≥ T, so latent / sóng âm với tham chiếu PC (graph
///    gốc). Dưới cổng (rác kiểu tháng 10) ⇒ không chạy lượt Core ML.
enum VieNeuCoreMLPreparer {
    struct Report: Sendable {
        var lines: [String] = []
        var sessionCap = 2
        /// RAM lớn nhất một session Core ML chiếm khi giữ (đo được), để lượt đọc kiểm RAM trước mỗi lần nạp.
        var sessionEstimateMB = 300.0
        /// Số session Core ML đã nạp sẵn ở cuối bước chuẩn bị (giữ tới hết lượt Core ML).
        var preloadedSessions = 0
        var passed = false
    }

    /// Cổng tự kiểm: rác (nhiễu như tháng 10) ra quanh 0 dB; fp32 đúng ra > 80 dB.
    static let minimumLatentDB = 40.0
    static let minimumWaveDB = 30.0
    /// RAM trống tối thiểu phải còn sau khi giữ các session Core ML (lượt đọc còn trình phát + đệm).
    static let minimumHeadroomMB = 600.0
    /// Engine Nano (ORT 4 graph + bộ phiên âm) bị nhả trong lúc chuẩn bị và nạp lại trước các lượt đọc.
    static let engineReloadMB = 380.0
    /// RAM trống tối thiểu trước khi biên dịch một graph (biên dịch VE giữ cùng lúc bản chép trọng số của ORT, gói
    /// MLProgram và model đã biên dịch).
    static let minimumCompileHeadroomMB = 1_000.0

    enum PrepareError: LocalizedError {
        case lowMemory(String)

        var errorDescription: String? {
            switch self {
            case .lowMemory(let summary):
                return "RAM trống không đủ để biên dịch Core ML (\(summary)). Tắt bớt app khác (vuốt khỏi đa nhiệm) rồi bấm lại."
            }
        }
    }
    /// Ước dung lượng cache biên dịch mỗi bucket (fp32): VE ~153 MB, codec ~99 MB, cộng dư.
    static let veCacheEstimateMB = 170.0
    static let codecCacheEstimateMB = 115.0

    static func requiredCacheMB(_ manifest: VieNeuCoreMLPackage.Manifest) -> Double {
        Double(manifest.veBuckets.count) * veCacheEstimateMB + Double(manifest.codecBuckets.count) * codecCacheEstimateMB
    }

    /// `progress` được gọi **trước** mỗi bước nặng (chỗ gọi ghi nhật ký `VieNeuAutoRunTrail` ở đó).
    static func prepare(
        backend: VieNeuCoreMLFlowBackend,
        progress: @Sendable (String) -> Void
    ) throws -> Report {
        let package = backend.package
        let manifest = backend.manifest
        var report = Report()
        try FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        let graphs = manifest.veBuckets.sorted().map { ("ve", $0) } + manifest.codecBuckets.sorted().map { ("codec", $0) }

        // 1. Biên dịch lạnh, từng graph một — dọn bản biên dịch dở của lượt bị giết trước đó.
        report.lines.append("— Biên dịch Core ML (lần đầu; có bản lưu thì là nạp lại) —")
        let removed = package.removeIncompleteCacheEntries()
        if removed > 0 {
            progress("Dọn \(removed) bản biên dịch dở của lượt trước")
            report.lines.append("dọn \(removed) bản biên dịch dở của lượt trước")
        }
        backend.setSessionCap(64)
        var largestHeldMB = 0.0
        for (index, (kind, bucket)) in graphs.enumerated() {
            try Task.checkCancellation()
            progress("Biên dịch Core ML \(index + 1)/\(graphs.count): \(kind) T\(bucket)…")
            backend.releaseSessions()
            let before = ProcessMemoryProbe.snapshot()
            // Bản 1.3.890 bị iOS giết ở bước 3–4/7 (biên dịch VE T128 / T160). Thiếu RAM thì dừng có báo, không để chết.
            if before.availableMB > 0, before.availableMB < minimumCompileHeadroomMB {
                throw PrepareError.lowMemory(before.summary)
            }
            let logURL = package.resultsURL.appendingPathComponent("compile-\(kind)\(bucket).log")
            let ms = try backend.loadSession(kind: kind, bucket: bucket, logPath: logURL.path)
            let held = ProcessMemoryProbe.snapshot()
            largestHeldMB = max(largestHeldMB, held.footprintMB - before.footprintMB)
            report.lines.append(String(
                format: "%@ T%ld: %.1f s · RAM +%.0f MB khi giữ session · %@", kind, bucket, ms / 1_000,
                held.footprintMB - before.footprintMB, partitionNote(logURL)
            ))
        }
        backend.releaseSessions()

        // 2. Nạp ấm, từng session một rồi nhả (không cộng dồn).
        report.lines.append("— Nạp lại từ bản biên dịch (ấm, từng session một) —")
        for (kind, bucket) in graphs {
            try Task.checkCancellation()
            progress("Nạp lại \(kind) T\(bucket)…")
            backend.releaseSessions()
            let before = ProcessMemoryProbe.snapshot()
            let ms = try backend.loadSession(kind: kind, bucket: bucket)
            let held = ProcessMemoryProbe.snapshot()
            largestHeldMB = max(largestHeldMB, held.footprintMB - before.footprintMB)
            report.lines.append(String(format: "%@ T%ld: %.2f s · RAM +%.0f MB khi giữ · %@", kind, bucket, ms / 1_000,
                                       held.footprintMB - before.footprintMB, held.summary))
        }
        backend.releaseSessions()
        // Trần lúc đọc: RAM trống bây giờ (engine Nano đang nhả) − engine nạp lại − chừa, chia RAM lớn nhất một session.
        let idle = ProcessMemoryProbe.snapshot()
        // Đo trên máy (1.3.907): giữ một session Core ML chỉ thêm ~20 MB footprint (trọng số đã biên dịch được map từ
        // đĩa) — sàn 150 MB cũ làm trần ra 6/7, thiếu một bucket phải nạp giữa lượt lúc khoá màn.
        report.sessionEstimateMB = max(40, largestHeldMB)
        backend.sessionEstimateMB = report.sessionEstimateMB
        let budget = idle.availableMB - engineReloadMB - minimumHeadroomMB
        let fit = idle.availableMB > 0 ? Int(budget / report.sessionEstimateMB) : 2
        report.sessionCap = min(graphs.count, max(2, fit))
        backend.setSessionCap(report.sessionCap)
        report.lines.append(String(
            format: "RAM lớn nhất một session %.0f MB · lúc nghỉ %@ ⇒ giữ tối đa %ld/%ld session khi đọc · cache %@",
            report.sessionEstimateMB, idle.summary, report.sessionCap, graphs.count,
            ByteCountFormatter.string(fromByteCount: package.cacheBytes, countStyle: .file)
        ))

        // 3. Tự kiểm mọi bucket với golden.
        report.lines.append("— Tự kiểm (so tham chiếu PC, graph gốc) —")
        report.passed = try selfTest(backend: backend, report: &report, progress: progress)
        report.lines.append(report.passed
            ? "✅ Core ML qua cổng (latent ≥ \(Int(minimumLatentDB)) dB, sóng âm ≥ \(Int(minimumWaveDB)) dB, không NaN)"
            : "❌ Core ML KHÔNG qua cổng ⇒ bỏ lượt Core ML")

        // 4. Nạp sẵn mọi session **ngay bây giờ** (màn còn sáng) và giữ tới hết lượt Core ML (1.3.909): lần đo 1.3.907
        // chết đúng lúc nạp session Core ML đầu tiên khi máy đã khoá màn ~17 phút (bước chuẩn bị ở tiền cảnh thì chạy).
        if report.passed {
            let loaded = try backend.preload(onStep: { progress("Nạp sẵn \($0) (màn còn sáng)") })
            report.preloadedSessions = loaded.count
            report.lines.append(String(
                format: "nạp sẵn %ld/%ld session trong %.1f s, giữ tới hết lượt Core ML · %@",
                loaded.count, backend.preloadOrder.count, loaded.ms / 1_000, ProcessMemoryProbe.snapshot().summary
            ))
        }
        backend.resetStats()
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
