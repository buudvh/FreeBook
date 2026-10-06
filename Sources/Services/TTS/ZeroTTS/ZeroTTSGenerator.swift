import Foundation

/// Vòng sinh frame của ZeroTTS — port từ `generateFrames` của bản JS (`js/src/synthesizer.ts`) và
/// `zerotts/synthesizer.py`.
///
/// Trình tự **phải** đúng như sau, lệch một bước là audio hỏng mà không có lỗi nào:
///
/// ```text
/// text_encoder(ids)            → cross_kv, text_valid, soa_embed     (một lần cho cả utterance)
/// prefix_step (cold start)     → hidden, packed_kv, full_valid
/// lặp t:
///   local_frame_decode(hidden) → is_eoa, codes
///   cập nhật seen_mask         → seen_mask[c][codes[c]] = true
///   nếu chưa có đuôi và is_eoa → tail = eoa_extra_frames
///   dừng nếu đuôi đã hết hoặc t ≥ max_frames
///   prefix_step (frame)        → hidden, packed_kv, full_valid   (pos = V + 1 + t)
/// codec decode_full(codes)     → PCM mono 48 kHz
/// ```
///
/// Ba điểm đã có bẫy ghi rõ ở upstream và được giữ nguyên ở đây:
/// - `forbid_eoa` bật khi `t < min_frames` **hoặc** đang trong đuôi — nếu không, model dừng ngay frame đầu.
/// - `tail` tồn tại vì kênh điều khiển và kênh audio giải mã từ **cùng** một hidden: frame bật `<eoa>` đã
///   có code hợp lệ, và bỏ nó là cắt cụt âm cuối.
/// - `cross_kv` **không** đổi trong suốt utterance nên chỉ tính một lần rồi truyền lại mọi frame.
final class ZeroTTSGenerator {
    struct Output {
        let samples: [Float]
        let frameCount: Int
        let sampleRate: Int
        let synthesisMs: Double
    }

    enum GeneratorError: LocalizedError {
        case badVoiceEmbedding(String)
        case badCrossKvShape(String)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .badVoiceEmbedding(let detail): return "Embedding giọng không khớp config: \(detail)"
            case .badCrossKvShape(let detail): return "`cross_kv` có hình dạng lạ: \(detail)"
            case .emptyResult: return "Model không sinh frame nào — văn bản quá ngắn hoặc bị cắt hết."
            }
        }
    }

    let runtime: ZeroTTSONNXRuntime
    let config: ZeroTTSConfig
    let tokenizer: ZeroTTSTokenizer
    let voiceEmbedding: [Float]
    let sampling: ZeroTTSConfig.Sampling
    let seed: UInt64

    init(runtime: ZeroTTSONNXRuntime, config: ZeroTTSConfig, tokenizer: ZeroTTSTokenizer,
         voiceEmbedding: [Float], sampling: ZeroTTSConfig.Sampling, seed: UInt64) {
        self.runtime = runtime
        self.config = config
        self.tokenizer = tokenizer
        self.voiceEmbedding = voiceEmbedding
        self.sampling = sampling
        self.seed = seed
    }

    func synthesize(text: String) throws -> Output {
        let started = ProcessInfo.processInfo.systemUptime
        let batch = 1
        let voiceCount = config.nVoiceQueries
        let dModel = config.dModel
        let codebooks = config.numCodebooks

        guard voiceEmbedding.count == voiceCount * dModel else {
            throw GeneratorError.badVoiceEmbedding(
                "có \(voiceEmbedding.count) float, cần \(voiceCount) × \(dModel) = \(voiceCount * dModel)")
        }

        let ids = tokenizer.encode(text)
        let length = ids.count

        // 1. text_encoder — một lần cho cả utterance.
        let encoded = try runtime.textEncoder(
            ids: ids, batch: batch, length: length,
            soaCapacity: batch * dModel,
            crossKvCapacity: config.nLayers * 2 * batch * config.nHeads * length * config.headDim
        )
        try validate(crossKvShape: encoded.crossKvShape, batch: batch, length: length)

        // 2. Cold start: `external_embed = [voice ‖ soa]`.
        try runtime.beginSequence(batch: batch, voiceCount: voiceCount, maxFrames: sampling.maxFrames,
                                  layers: config.nLayers, heads: config.nHeads, headDim: config.headDim)
        var external = [Float](repeating: 0, count: batch * (voiceCount + 1) * dModel)
        external.replaceSubrange(0..<(voiceCount * dModel), with: voiceEmbedding)
        external.replaceSubrange((voiceCount * dModel)..<((voiceCount + 1) * dModel), with: encoded.soa)

        var hidden = try runtime.prefixInit(
            externalEmbed: external, soa: encoded.soa,
            crossKv: encoded.crossKv, crossKvShape: encoded.crossKvShape,
            textValid: encoded.textValid, batch: batch, dModel: dModel
        )

        // 3. Vòng frame.
        var seenMask = [UInt8](repeating: 0, count: codebooks * config.codebookSize)
        var frames: [[Int64]] = []
        frames.reserveCapacity(min(sampling.maxFrames, 256))
        var random = ZeroTTSRandom(seed: seed)
        var tail: Int?
        var index = 0

        while true {
            try Task.checkCancellation()
            let decoded = try runtime.localFrameDecode(
                hidden: hidden, batch: batch, dModel: dModel,
                forbidEoa: index < sampling.minFrames || tail != nil,
                sampling: sampling, seenMask: &seenMask,
                ctrlRandomU: random.nextUniform(),
                audioRandomU: random.fill(count: codebooks),
                codebooks: codebooks
            )
            if tail == nil && decoded.isEoa { tail = max(0, sampling.eoaExtraFrames) }
            if let remaining = tail, remaining <= 0 { break }
            if index >= sampling.maxFrames { break }

            frames.append(decoded.codes)

            if var remaining = tail {
                remaining -= 1
                tail = remaining
                if remaining <= 0 { break }
            }

            hidden = try runtime.prefixFrame(
                frameCodes: decoded.codes, frameIndex: index, voiceCount: voiceCount,
                crossKv: encoded.crossKv, crossKvShape: encoded.crossKvShape,
                textValid: encoded.textValid, batch: batch, dModel: dModel
            )
            index += 1
        }

        guard !frames.isEmpty else { throw GeneratorError.emptyResult }

        // 4. Codec: `(K, T)` int32 theo bố cục vòng sinh, cầu nối tự chuyển vị.
        var codesKT = [Int32](repeating: 0, count: codebooks * frames.count)
        for (frameIndex, frame) in frames.enumerated() {
            for codebook in 0..<min(codebooks, frame.count) {
                codesKT[codebook * frames.count + frameIndex] = Int32(truncatingIfNeeded: frame[codebook])
            }
        }
        // Trần dung lượng PCM: độ dài lý thuyết + biên, để `codecDecode` báo lỗi rõ nếu model trả dài hơn.
        let expectedSamples = Double(frames.count) * config.secondsPerFrame * Double(config.sampleRate)
        let pcmCapacity = Int(expectedSamples.rounded(.up)) + 8192
        let samples = try runtime.codecDecode(codesKT: codesKT, codebooks: codebooks,
                                              frames: frames.count, pcmCapacity: pcmCapacity)

        return Output(samples: samples,
                      frameCount: frames.count,
                      sampleRate: config.sampleRate,
                      synthesisMs: (ProcessInfo.processInfo.systemUptime - started) * 1_000)
    }

    /// Đối chiếu `cross_kv` trả về với `config.json`. Lệch ở đây nghĩa là config không thuộc bộ weights —
    /// và nếu không chặn, lỗi sẽ nổ ở `prefix_step` với thông báo khó hiểu về shape.
    private func validate(crossKvShape: [Int64], batch: Int, length: Int) throws {
        guard crossKvShape.count == 6 else {
            throw GeneratorError.badCrossKvShape("hạng \(crossKvShape.count), cần 6")
        }
        let expected: [Int64] = [Int64(config.nLayers), 2, Int64(batch), Int64(config.nHeads),
                                 Int64(length), Int64(config.headDim)]
        guard crossKvShape == expected else {
            throw GeneratorError.badCrossKvShape("\(crossKvShape) ≠ \(expected) — `config.json` không khớp weights")
        }
    }
}
