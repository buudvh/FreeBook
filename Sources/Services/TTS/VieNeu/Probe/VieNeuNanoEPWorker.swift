import Foundation

/// Phần **tính** của phép thử P1 "So EP cho Nano" — chạy ngoài MainActor, mỗi lần một cấu hình EP, nhả session
/// trước khi sang cấu hình kế (Core ML biên dịch tạo thêm bản sao trọng số; iPhone 11 không dư RAM).
///
/// Mỗi cấu hình: dựng prep (CPU) + `vector_estimator` main T128 + codec T128 bằng EP đó, chạy trọn quỹ đạo 8 bước +
/// CFG 3 cho 5 đoạn golden, đo ms + CPU-ms từng lượt, so v bước 0 / latent / sóng âm với **cấu hình CPU trên chính
/// máy** (cấu hình CPU thì so với tham chiếu PC). Core ML / CPU còn thử main T234 + T256 (external data) ở bước 0 của
/// một đoạn ⇒ kiểm giả thuyết H1 (lỗi T234 tháng 10 do chiều 234 không chia hết 32).
enum VieNeuNanoEPWorker {
    struct Config: Sendable {
        let id: String
        let title: String
        let provider: String
        let computeUnits: String?
        let threads: Int32

        var isCoreML: Bool { provider == "CoreML" }
    }

    typealias Tensor = VieNeuONNXProbeSession.Tensor

    static let configs: [Config] = [
        Config(id: "cpu", title: "ORT CPU · graph tĩnh (tham chiếu trên máy)", provider: "CPU", computeUnits: nil, threads: 2),
        Config(id: "coreml-cpu", title: "Core ML · CPU-only (fp32)", provider: "CoreML", computeUnits: "CPUOnly", threads: 2),
        Config(id: "coreml-gpu", title: "Core ML · CPU + GPU", provider: "CoreML", computeUnits: "CPUAndGPU", threads: 2),
        Config(id: "coreml-ane", title: "Core ML · CPU + Neural Engine", provider: "CoreML", computeUnits: "CPUAndNeuralEngine", threads: 2),
        Config(id: "xnnpack", title: "XNNPACK (fp32)", provider: "XNNPACK", computeUnits: nil, threads: 1)
    ]

    /// Cổng của Core ML CPU-only: dưới mức này (hoặc có NaN / lỗi) là tháng 10 lặp lại ⇒ bỏ qua GPU + ANE.
    static let coreMLCPUGateDB = 60.0
    static let cfg: Float = 3

    struct ChunkOutput: Sendable {
        let v0: [Float]
        let latent: [Float]
        let wav: [Float]
    }

    struct ConfigResult: Sendable {
        let config: Config
        var status = "chưa chạy"
        var memoryBefore = ""
        var createMs: [String: Double] = [:]
        var veMs: [Double] = []
        var veCpuMs: [Double] = []
        var codecMs: [Double] = []
        var codecCpuMs: [Double] = []
        var snrV0: [Double] = []
        var snrLatent: [Double] = []
        var snrWav: [Double] = []
        var nanCount = 0
        var h1: [String] = []
        var logExcerpt: [String] = []
        var wav: [Float] = []
        var completed = false
    }

    struct Sessions {
        let prep: VieNeuONNXProbeSession
        let main: VieNeuONNXProbeSession
        let codec: VieNeuONNXProbeSession?
        let bucket: Int
    }

    // MARK: - Một cấu hình

    /// `baseline` = đầu ra của cấu hình CPU trên máy (nil khi đang chạy chính nó ⇒ so với tham chiếu PC).
    static func run(
        config: Config,
        package: VieNeuNanoStaticPackage,
        manifest: VieNeuNanoStaticPackage.Manifest,
        golden: VieNeuNanoGolden,
        baseline: [ChunkOutput]?,
        progress: @Sendable (String) -> Void
    ) throws -> (ConfigResult, [ChunkOutput]) {
        var result = ConfigResult(config: config)
        result.memoryBefore = ProcessMemoryProbe.snapshot().summary
        var outputs: [ChunkOutput] = []
        let bucket = manifest.veInlineBucket
        do {
            guard manifest.codecBucket == bucket else {
                throw VieNeuONNXProbeSession.ProbeError.failure("bucket VE \(bucket) ≠ codec \(manifest.codecBucket)")
            }
            progress("\(config.title): dựng session (Core ML lần đầu phải biên dịch, có thể lâu)…")
            let prep = try makeSession(package.url("ve_prep_T\(bucket).onnx"), provider: "CPU", config: config,
                                       package: package, key: "prep", result: &result)
            let main = try makeSession(package.url("ve_main_T\(bucket).onnx"), provider: config.provider, config: config,
                                       package: package, key: "main", result: &result)
            let codec = try makeSession(package.url("codec_T\(bucket).onnx"), provider: config.provider, config: config,
                                        package: package, key: "codec", result: &result)
            let sessions = Sessions(prep: prep, main: main, codec: codec, bucket: bucket)
            for (index, chunk) in golden.chunks.enumerated() {
                try Task.checkCancellation()
                progress("\(config.title): đoạn \(index + 1)/\(golden.chunks.count)")
                outputs.append(try trajectory(sessions, chunk: chunk, golden: golden, result: &result))
            }
            for (index, chunk) in golden.chunks.enumerated() {
                let reference = baseline?[index] ?? ChunkOutput(v0: chunk.v0, latent: chunk.latent, wav: chunk.wav)
                result.snrV0.append(snr(reference.v0, outputs[index].v0))
                result.snrLatent.append(snr(reference.latent, outputs[index].latent))
                result.snrWav.append(snr(reference.wav, outputs[index].wav))
            }
            result.wav = joinedWav(outputs)
            result.completed = true
            result.status = "xong"
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            result.status = "lỗi: \(error.localizedDescription)"
            AppLogger.shared.log("❌ [VieNeuProbe] \(config.title): \(error.localizedDescription)")
        }
        if config.provider != "XNNPACK" {
            try Task.checkCancellation()
            progress("\(config.title): thử T234 / T256 (H1)…")
            result.h1 = h1(config: config, package: package, manifest: manifest, golden: golden,
                           baselineV0: baseline?[manifest.h1Chunk].v0, result: &result)
        }
        return (result, outputs)
    }

    /// Cấu hình Core ML CPU-only có qua cổng không (quyết có chạy tiếp GPU / ANE).
    static func passesCoreMLGate(_ result: ConfigResult) -> Bool {
        result.completed && result.nanCount == 0 && (result.snrV0.min() ?? -.infinity) >= coreMLCPUGateDB
    }

    // MARK: - Session

    static func makeSession(
        _ url: URL,
        provider: String,
        config: Config,
        package: VieNeuNanoStaticPackage,
        key: String,
        result: inout ConfigResult
    ) throws -> VieNeuONNXProbeSession {
        var options: [String: String] = [:]
        if provider == "CoreML" {
            // **Không** đặt `ModelCacheDirectory`: mỗi lượt chỉ dựng một session mỗi graph nên cache không giúp gì, mà
            // giữ lại bản biên dịch fp32 của 4 graph × 3 compute unit tốn hơn 1,5 GB đĩa; thư mục tạm của ORT tự xoá khi
            // đóng session. Khoá cache của EP chỉ là hash model (bài học tháng 10) ⇒ không cache cũng loại hẳn chuyện ANE
            // dùng lại bản đã biên dịch cho CPU-only.
            options = ["ModelFormat": "MLProgram", "MLComputeUnits": config.computeUnits ?? "ALL",
                       "RequireStaticInputShapes": "1", "ProfileComputePlan": "1"]
        } else if provider == "XNNPACK" {
            options = ["intra_op_num_threads": "2"]
        }
        try? FileManager.default.createDirectory(at: package.resultsURL, withIntermediateDirectories: true)
        let logURL = package.resultsURL.appendingPathComponent("\(config.id)-\(url.deletingPathExtension().lastPathComponent).log")
        let started = ProcessInfo.processInfo.systemUptime
        let session = try VieNeuONNXProbeSession(
            modelPath: url.path, provider: provider, options: options,
            threads: provider == "CPU" && key == "prep" ? 1 : config.threads, logPath: provider == "CPU" ? "" : logURL.path
        )
        result.createMs[key] = (ProcessInfo.processInfo.systemUptime - started) * 1_000
        if provider != "CPU" { result.logExcerpt += logExcerpt(logURL, label: "\(key) \(url.lastPathComponent)") }
        return session
    }

    // MARK: - Quỹ đạo

    static func velocity(
        _ sessions: Sessions, x: [Float], t: Float, ctx: [Float], ctxMask: [Float], spk: [Float], style: [Float],
        frames: Int, result: inout ConfigResult, timed: Bool
    ) throws -> [Float] {
        var frameMask = [Float](repeating: 0, count: sessions.bucket)
        for index in 0..<min(frames, sessions.bucket) { frameMask[index] = 1 }
        var feeds = try sessions.prep.run([
            "frame_mask": Tensor(values: frameMask, shape: [1, Int64(sessions.bucket)]),
            "ctx_mask": Tensor(values: ctxMask, shape: [1, Int64(VieNeuNanoGolden.contextLength)]),
            "t": Tensor(values: [t], shape: [1])
        ])
        feeds["x"] = Tensor(values: x, shape: [1, Int64(VieNeuNanoGolden.channels), Int64(sessions.bucket)])
        feeds["ctx"] = Tensor(values: ctx, shape: [1, Int64(VieNeuNanoGolden.contextLength), Int64(VieNeuNanoGolden.styleDim)])
        feeds["spk"] = Tensor(values: spk, shape: [1, Int64(spk.count)])
        feeds["style"] = Tensor(values: style, shape: [1, Int64(style.count / VieNeuNanoGolden.styleDim), Int64(VieNeuNanoGolden.styleDim)])
        let wallStart = ProcessInfo.processInfo.systemUptime
        let cpuStart = ProcessCPUClock.nowMs()
        let outputs = try sessions.main.run(feeds)
        if timed {
            result.veMs.append((ProcessInfo.processInfo.systemUptime - wallStart) * 1_000)
            result.veCpuMs.append(ProcessCPUClock.nowMs() - cpuStart)
        }
        guard let name = sessions.main.outputNames.first, let v = outputs[name]?.values else {
            throw VieNeuONNXProbeSession.ProbeError.failure("vector_estimator không trả output")
        }
        return v
    }

    static func trajectory(
        _ sessions: Sessions, chunk: VieNeuNanoGolden.Chunk, golden: VieNeuNanoGolden, result: inout ConfigResult
    ) throws -> ChunkOutput {
        let channels = VieNeuNanoGolden.channels
        let bucket = sessions.bucket
        let frames = chunk.frames
        var x = pad(chunk.x0, frames: frames, bucket: bucket)
        var v0: [Float] = []
        for step in 0..<(golden.grid.count - 1) {
            let t = golden.grid[step]
            let v = try velocity(sessions, x: x, t: t, ctx: chunk.ctx, ctxMask: chunk.ctxMask, spk: golden.spk,
                                 style: golden.style, frames: frames, result: &result, timed: true)
            let vu = try velocity(sessions, x: x, t: t, ctx: golden.nullCtx, ctxMask: golden.nullCtxMask,
                                  spk: golden.nullSpk, style: golden.nullStyle, frames: frames, result: &result, timed: true)
            let dt = golden.grid[step + 1] - golden.grid[step]
            var combined = [Float](repeating: 0, count: channels * bucket)
            for index in 0..<combined.count {
                combined[index] = vu[index] + cfg * (v[index] - vu[index])
                x[index] += dt * combined[index]
            }
            if step == 0 { v0 = crop(combined, frames: frames, bucket: bucket) }
        }
        var wav: [Float] = []
        if let codec = sessions.codec {
            let wallStart = ProcessInfo.processInfo.systemUptime
            let cpuStart = ProcessCPUClock.nowMs()
            let outputs = try codec.run(["x": Tensor(values: x, shape: [1, Int64(channels), Int64(bucket)])])
            result.codecMs.append((ProcessInfo.processInfo.systemUptime - wallStart) * 1_000)
            result.codecCpuMs.append(ProcessCPUClock.nowMs() - cpuStart)
            guard let name = codec.outputNames.first, let samples = outputs[name]?.values else {
                throw VieNeuONNXProbeSession.ProbeError.failure("codec_decoder không trả output")
            }
            // Codec nhân quả ⇒ phần đệm cuối không ảnh hưởng `T × 1536` mẫu đầu.
            wav = Array(samples.prefix(frames * VieNeuNanoGolden.samplesPerFrame))
        }
        let latent = crop(x, frames: frames, bucket: bucket)
        result.nanCount += v0.filter(\.isNaN).count + latent.filter(\.isNaN).count + wav.filter(\.isNaN).count
        return ChunkOutput(v0: v0, latent: latent, wav: wav)
    }

    // MARK: - H1 (T234 so với T256)

    static func h1(
        config: Config, package: VieNeuNanoStaticPackage, manifest: VieNeuNanoStaticPackage.Manifest,
        golden: VieNeuNanoGolden, baselineV0: [Float]?, result: inout ConfigResult
    ) -> [String] {
        let chunk = golden.chunks[manifest.h1Chunk]
        let reference = baselineV0 ?? chunk.v0
        let label = baselineV0 == nil ? "PC" : "CPU máy"
        var lines: [String] = []
        for bucket in manifest.veExternalBuckets {
            do {
                let prep = try makeSession(package.url("ve_prep_T\(bucket).onnx"), provider: "CPU", config: config,
                                           package: package, key: "prep T\(bucket)", result: &result)
                let main = try makeSession(package.url("ve_main_T\(bucket).onnx"), provider: config.provider,
                                           config: config, package: package, key: "main T\(bucket)", result: &result)
                let sessions = Sessions(prep: prep, main: main, codec: nil, bucket: bucket)
                let x = pad(chunk.x0, frames: chunk.frames, bucket: bucket)
                let started = ProcessInfo.processInfo.systemUptime
                let v = try velocity(sessions, x: x, t: golden.grid[0], ctx: chunk.ctx, ctxMask: chunk.ctxMask,
                                     spk: golden.spk, style: golden.style, frames: chunk.frames, result: &result, timed: false)
                let vu = try velocity(sessions, x: x, t: golden.grid[0], ctx: golden.nullCtx, ctxMask: golden.nullCtxMask,
                                      spk: golden.nullSpk, style: golden.nullStyle, frames: chunk.frames, result: &result,
                                      timed: false)
                let ms = (ProcessInfo.processInfo.systemUptime - started) * 1_000 / 2
                let combined = zip(v, vu).map { $1 + cfg * ($0 - $1) }
                let value = snr(reference, crop(combined, frames: chunk.frames, bucket: bucket))
                lines.append("T\(bucket): v bước 0 \(format(value)) dB so với \(label) · \(String(format: "%.0f", ms)) ms/lượt")
            } catch {
                lines.append("T\(bucket): lỗi — \(error.localizedDescription)")
            }
        }
        return lines
    }
}
