import Foundation

/// Giao diện chung cho mọi bộ máy suy luận VieNeu-TTS: **ONNX Runtime** (`VieNeuONNXRuntime`) và
/// **Core ML** (`VieNeuCoreMLRuntime`). Cả hai phục vụ cùng một đường ống 4 bước
/// (`text_encoder` → `duration_predictor` → vòng Euler `vector_estimator` → `codec_decoder`), nên protocol
/// này khớp **nguyên chữ ký** 7 thành viên của `VieNeuONNXRuntime` cộng thêm `backendID` và một `runChunk`
/// cấp cao.
///
/// Dùng chung protocol cho phép `VieNeuTTSEngine` chuyển đổi bộ máy tại runtime và **rớt từng đoạn về ORT**
/// khi Core ML lỗi (plan §2 Q2) mà không đổi logic tổng hợp.
protocol VieNeuInferenceBackend: AnyObject {
    /// Định danh bộ máy (`"onnx"` / `"coreml"`) — dùng cho log và self-test.
    var backendID: String { get }

    /// `text_encoder(ids, style)` → `ctx` kèm **shape thật**.
    func textEncoder(ids: [Int64], style: [Float], styleRows: Int, styleColumns: Int) throws -> (values: [Float], shape: [Int64])

    /// `duration_predictor(ctx, ctx_mask, spk)` → `log_s`.
    func durationPredictor(context: [Float], contextShape: [Int64], mask: [UInt8], speaker: [Float]) throws -> Float

    /// `vector_estimator(x, t, ctx, ctx_mask, spk, style)` → velocity cùng shape với `x`.
    func vectorEstimator(latent: [Float], time: Float, context: [Float], contextShape: [Int64], mask: [UInt8], speaker: [Float], style: [Float], styleRows: Int, styleColumns: Int, latentChannels: Int, frames: Int) throws -> [Float]

    /// Nhánh **vô điều kiện** của CFG.
    func vectorEstimatorUnconditioned(latent: [Float], time: Float, nullContext: [Float], nullContextShape: [Int64], nullMask: [UInt8], nullSpeaker: [Float], nullStyle: [Float], styleRows: Int, styleColumns: Int, latentChannels: Int, frames: Int) throws -> [Float]

    /// `codec_decoder(x)` → PCM float32.
    func codecDecoder(latent: [Float], latentChannels: Int, frames: Int) throws -> [Float]

    /// Số frame **thực sự** dùng để suy luận, có thể khác `frames` tính từ duration.
    ///
    /// ONNX giữ shape động nên trả đúng `frames`. Core ML đóng băng mỗi graph ở một bucket `T` cố định
    /// (`VieNeuBucketSelector.bucketFrames`), nên phải **snap** `frames` lên bucket nhỏ nhất `≥ frames`
    /// — nếu không `vector_estimator`/`codec_decoder` nhận shape sai và Core ML ném.
    func effectiveFrames(_ frames: Int) -> Int

    /// Reset bộ đếm churn (chỉ có nghĩa với ORT; Core ML không đo).
    func resetChurnCounters()

    /// Ảnh chụp churn (ORT): (tạo, giải phóng, bytes). Core ML trả (0, 0, 0).
    var churnSnapshot: (Int64, Int64, Int64) { get }

    /// Tổng hợp **một chunk** thành PCM — cấp cao hơn, gọi đúng đường ống 4 bước. `VieNeuTTSEngine.runChunk`
    /// gọi hàm này và bọc try/catch để rớt về ORT khi ném.
    func runChunk(
        ids: [Int64],
        preset: VieNeuVoiceCatalog.Preset,
        tuning: VieNeuSynthesisPolicy.Tuning,
        speed: Double,
        config: VieNeuConfig,
        nullContext: [Float],
        nullContextShape: [Int64],
        nullMask: [UInt8],
        timing: inout VieNeuTTSEngine.Timing
    ) throws -> [Float]
}

/// Đường ống tổng hợp **một chunk** dùng chung cho mọi backend (ONNX lẫn Core ML). Tách ra hàm tự do để
/// cả hai backend cùng gọi, không lặp lại logic 4 bước ở hai chỗ.
///
/// Khớp từng bước với `VieNeuTTSEngine.runChunk` nguyên bản — bốn điểm cố ý (t warp bởi sway, thứ tự warp,
/// nhiễu chuẩn tắc, `rounded(.toNearestOrEven)`) đều giữ nguyên.
func vieNeuOrchestrateChunk(
    backend: VieNeuInferenceBackend,
    ids: [Int64],
    preset: VieNeuVoiceCatalog.Preset,
    tuning: VieNeuSynthesisPolicy.Tuning,
    speed: Double,
    config: VieNeuConfig,
    nullContext: [Float],
    nullContextShape: [Int64],
    nullMask: [UInt8],
    timing: inout VieNeuTTSEngine.Timing
) throws -> [Float] {
    let mask = ids.map { $0 == config.padID ? UInt8(0) : UInt8(1) }
    let chunkStarted = ProcessInfo.processInfo.systemUptime

    let context = try backend.textEncoder(ids: ids, style: preset.style, styleRows: config.nStyle, styleColumns: config.styleDim)

    let logSeconds = try backend.durationPredictor(context: context.values, contextShape: context.shape, mask: mask, speaker: preset.speakerEmbedding)
    let seconds = min(exp(Double(logSeconds)) / max(speed, 1e-3), VieNeuConfig.maxChunkSeconds)
    // Snap lên bucket gần nhất (≥ frames) với Core ML — ORT giữ shape động nên trả đúng `frames`.
    let frames = backend.effectiveFrames(max(VieNeuConfig.minFrames, Int((seconds * config.flowFPS).rounded(.toNearestOrEven))))

    var latent = [Float](repeating: 0, count: config.latentChannels * frames)
    VieNeuTTSEngine.fillStandardNormal(&latent)
    let steps = max(1, tuning.steps)
    let grid = VieNeuTTSEngine.timeGrid(steps: steps, sway: tuning.sway)

    let vectorStarted = ProcessInfo.processInfo.systemUptime

    for step in 0..<steps {
        try Task.checkCancellation()
        let conditioned = try backend.vectorEstimator(
            latent: latent, time: Float(grid[step]), context: context.values, contextShape: context.shape,
            mask: mask, speaker: preset.speakerEmbedding, style: preset.style,
            styleRows: config.nStyle, styleColumns: config.styleDim, latentChannels: config.latentChannels, frames: frames
        )
        var velocity = conditioned
        if tuning.cfg > 0 {
            let unconditioned = try backend.vectorEstimatorUnconditioned(
                latent: latent, time: Float(grid[step]), nullContext: nullContext, nullContextShape: nullContextShape,
                nullMask: nullMask, nullSpeaker: config.constants.nullSpeaker, nullStyle: config.constants.nullStyle,
                styleRows: config.nStyle, styleColumns: config.styleDim, latentChannels: config.latentChannels, frames: frames
            )
            for index in velocity.indices {
                velocity[index] = unconditioned[index] + tuning.cfg * (velocity[index] - unconditioned[index])
            }
        }
        let delta = Float(grid[step + 1] - grid[step])
        for index in latent.indices {
            latent[index] += delta * velocity[index]
        }
    }

    let waveform = try backend.codecDecoder(latent: latent, latentChannels: config.latentChannels, frames: frames)
    let vectorMs = (ProcessInfo.processInfo.systemUptime - vectorStarted) * 1_000
    let chunkMs = (ProcessInfo.processInfo.systemUptime - chunkStarted) * 1_000
    timing.vectorMs += vectorMs
    timing.otherMs += max(0, chunkMs - vectorMs)
    (timing.tensorCreates, timing.tensorReleases, timing.copiedBytes) = backend.churnSnapshot

    return VieNeuTTSEngine.trimAndFade(waveform, sampleRate: config.sampleRate)
}
