import Foundation

/// Vòng Euler + CFG và codec của **một chunk** (tách khỏi `runChunk` ở P1b): đường ORT như trước 1.3.889, hoặc một
/// `VieNeuFlowBackend` do lượt gọi truyền vào (Core ML của màn thử). Bước text_encoder + duration + nhiễu khởi tạo vẫn ở
/// `runChunk`, nên hai đường nhận **cùng** đầu vào.
extension VieNeuTTSEngine {
    /// Chạy vòng Euler rồi codec; bấm giờ `timing.vector` / `timing.codec` như cũ (chốt vòng Euler **trước** codec).
    func runFlow(
        _ request: VieNeuFlowRequest,
        backend: VieNeuFlowBackend?,
        runtime: VieNeuONNXRuntime,
        clock: inout StageClock,
        timing: inout Timing
    ) throws -> [Float] {
        if let backend, backend.canRun(request) {
            do {
                let latent = try backend.trajectory(request)
                clock.lap(&timing.vector)
                let waveform = try backend.decode(latent: latent, frames: request.frames, latentChannels: request.latentChannels)
                clock.lap(&timing.codec)
                return waveform
            } catch let error where backend.fallsBackToORTOnError && !(error is CancellationError) {
                // Trình đọc (P2c): Core ML lỗi ở chunk này ⇒ chạy lại bằng ORT ngay dưới, không mất tiếng (thời gian lượt
                // hỏng tính vào chặng ORT kế tiếp).
                backend.noteFailure(error)
            }
        } else {
            backend?.noteFallback(request)
        }
        let latent = try runEulerORT(request, runtime: runtime)
        clock.lap(&timing.vector) // chốt TRƯỚC codec — trước 1.3.878 chốt sau nên codec bị tính vào vòng Euler
        let waveform = try runtime.codecDecoder(latent: latent, latentChannels: request.latentChannels, frames: request.frames)
        clock.lap(&timing.codec)
        return waveform
    }

    /// Vòng Euler + CFG qua ORT — nguyên văn đường cũ của `runChunk`.
    private func runEulerORT(_ request: VieNeuFlowRequest, runtime: VieNeuONNXRuntime) throws -> [Float] {
        var latent = request.latent
        let grid = request.grid
        for step in 0..<(grid.count - 1) {
            try Task.checkCancellation()
            let conditioned = try runtime.vectorEstimator(
                latent: latent,
                time: Float(grid[step]),
                context: request.context,
                contextShape: request.contextShape,
                mask: request.mask,
                speaker: request.speaker,
                style: request.style,
                styleRows: request.styleRows,
                styleColumns: request.styleColumns,
                latentChannels: request.latentChannels,
                frames: request.frames
            )
            var velocity = conditioned
            if request.cfg > 0 {
                let unconditioned = try runtime.vectorEstimatorUnconditioned(
                    latent: latent, time: Float(grid[step]), nullContext: request.nullContext,
                    nullContextShape: request.nullContextShape, nullMask: request.nullMask,
                    nullSpeaker: request.nullSpeaker, nullStyle: request.nullStyle,
                    styleRows: request.styleRows, styleColumns: request.styleColumns,
                    latentChannels: request.latentChannels, frames: request.frames
                )
                // v = vu + cfg × (v − vu)
                for index in velocity.indices {
                    velocity[index] = unconditioned[index]
                        + request.cfg * (velocity[index] - unconditioned[index])
                }
            }
            let delta = Float(grid[step + 1] - grid[step])
            for index in latent.indices {
                latent[index] += delta * velocity[index]
            }
        }
        return latent
    }
}
