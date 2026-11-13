import Foundation

/// **Tự kiểm golden** của "Tăng tốc Core ML" (`VieNeuCoreMLAccelerator.compileAndVerify` gọi sau khi biên dịch): mỗi
/// đoạn golden × mọi bucket VE ≥ T × mọi bucket codec ≥ T, so latent / sóng âm với tham chiếu PC (graph gốc). Dưới cổng
/// (rác kiểu tháng 10) ⇒ không gắn backend, trình đọc giữ ORT. Chạy ngoài MainActor.
enum VieNeuCoreMLPreparer {
    /// Cổng tự kiểm: rác (nhiễu như tháng 10) ra quanh 0 dB; fp32 đúng ra > 80 dB.
    static let minimumLatentDB = 40.0
    static let minimumWaveDB = 30.0
    /// Hệ số CFG của đoạn golden — đúng giá trị lúc dựng tham chiếu trên PC (`Scripts/vieneu_nano_static_export.py`).
    static let goldenCFG: Float = 3

    /// Tự kiểm golden mọi bucket; qua cổng mới gắn backend cho trình đọc. Trả kết quả + từng dòng số đo (để log).
    static func verify(
        backend: VieNeuCoreMLFlowBackend,
        progress: @Sendable (String) -> Void
    ) throws -> (passed: Bool, lines: [String]) {
        var lines: [String] = []
        let passed = try selfTest(backend: backend, lines: &lines, progress: progress)
        return (passed, lines)
    }

    private static func selfTest(
        backend: VieNeuCoreMLFlowBackend,
        lines: inout [String],
        progress: @Sendable (String) -> Void
    ) throws -> Bool {
        let manifest = backend.manifest
        let golden = try VieNeuNanoGolden(url: backend.package.url("golden.npz"), chunkCount: manifest.goldenChunks)
        var passed = true
        for (index, chunk) in golden.chunks.enumerated() {
            let request = goldenRequest(chunk, golden: golden, manifest: manifest)
            for veBucket in manifest.veBuckets.sorted() where veBucket >= chunk.frames {
                try Task.checkCancellation()
                progress("Tự kiểm đoạn \(index + 1)/\(golden.chunks.count) · VE T\(veBucket)…")
                let latent = try backend.trajectory(request, veBucket: veBucket)
                let latentDB = snr(chunk.latent, latent)
                var parts = ["latent \(format(latentDB))"]
                var nan = latent.contains(where: \.isNaN)
                passed = passed && latentDB >= minimumLatentDB
                for codecBucket in manifest.codecBuckets.sorted() where codecBucket >= chunk.frames {
                    let wave = try backend.decode(
                        latent: latent, frames: chunk.frames, latentChannels: VieNeuNanoGolden.channels,
                        codecBucket: codecBucket
                    )
                    let waveDB = snr(chunk.wav, wave)
                    nan = nan || wave.contains(where: \.isNaN)
                    passed = passed && waveDB >= minimumWaveDB
                    parts.append("codec T\(codecBucket) \(format(waveDB))")
                }
                passed = passed && !nan
                lines.append("đoạn \(index + 1) (T=\(chunk.frames)) VE T\(veBucket): \(parts.joined(separator: " · ")) dB\(nan ? " · NaN!" : "")")
            }
        }
        return passed
    }

    /// Request của một đoạn golden (ctx đệm tới `lengthFrozen`, CFG như lúc dựng tham chiếu).
    static func goldenRequest(
        _ chunk: VieNeuNanoGolden.Chunk,
        golden: VieNeuNanoGolden,
        manifest: VieNeuCoreMLPackage.Manifest
    ) -> VieNeuFlowRequest {
        let shape: [Int64] = [1, Int64(manifest.lengthFrozen), Int64(VieNeuCoreMLFlowBackend.contextDim)]
        return VieNeuFlowRequest(
            latent: chunk.x0, frames: chunk.frames, latentChannels: VieNeuNanoGolden.channels,
            grid: golden.grid.map { Double($0) }, cfg: goldenCFG,
            context: chunk.ctx, contextShape: shape, mask: chunk.ctxMask.map { $0 > 0.5 ? UInt8(1) : UInt8(0) },
            speaker: golden.spk, style: golden.style, styleRows: golden.style.count / VieNeuCoreMLFlowBackend.contextDim,
            styleColumns: VieNeuCoreMLFlowBackend.contextDim,
            nullContext: golden.nullCtx, nullContextShape: shape,
            nullMask: golden.nullCtxMask.map { $0 > 0.5 ? UInt8(1) : UInt8(0) },
            nullSpeaker: golden.nullSpk, nullStyle: golden.nullStyle
        )
    }

    /// SNR (dB) của `test` so với `reference` trên phần chung; NaN ⇒ −∞, trùng tuyệt đối ⇒ +∞.
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
}
