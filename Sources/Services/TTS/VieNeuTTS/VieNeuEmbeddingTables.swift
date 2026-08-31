import Accelerate
import Foundation

/// Bảng embedding **tied** của VieNeu: vừa dùng để tra khi dựng input, vừa dùng làm ma trận đầu ra
/// khi tính logits. Đây là lý do chúng không nằm trong graph ONNX mà ở một file `.npz` riêng.
///
/// Kích thước: `audioEmbedding` = 16 × 1024 × 768 float ≈ 50.3 MB, `textEmbedding` = 419 × 768 ≈
/// 1.29 MB. Giữ dạng `[Float]` phẳng, không phải mảng lồng: mỗi frame audio phải nhân ma trận 16
/// lần nên `cblas_sgemv` cần con trỏ liên tục.
final class VieNeuEmbeddingTables: @unchecked Sendable {
    private let config: VieNeuModelConfig
    private let textEmbedding: [Float]
    private let audioEmbedding: [Float]

    /// Phép chiếu x-vector → không gian hidden. Chỉ có khi `use_speaker_embedding = true`.
    private let xvecWeight: [Float]?
    private let xvecBias: [Float]?
    private let xvecLayerNormWeight: [Float]?
    private let xvecLayerNormBias: [Float]?
    private let xvecLayerNormEpsilon: Float

    var hiddenSize: Int { config.hiddenSize }
    var codebookCount: Int { config.codebookCount }
    var audioVocabSize: Int { config.audioVocabSize }
    var textVocabSize: Int { config.textVocabSize }
    /// `false` khi bộ model cần speaker embedding nhưng npz không có `xvec_*` — dấu hiệu bộ model
    /// và npz lệch nhau, phải báo lỗi rõ chứ không im lặng đọc sai giọng.
    var canBuildSpeakerAnchor: Bool { xvecWeight != nil }

    init(npzURL: URL, config: VieNeuModelConfig) throws {
        self.config = config
        let archive = try VieNeuNPZArchive(url: npzURL)

        self.textEmbedding = try archive.floatArray(
            named: "text_emb",
            expectedCount: config.textVocabSize * config.hiddenSize
        )
        self.audioEmbedding = try archive.floatArray(
            named: "audio_emb",
            expectedCount: config.codebookCount * config.audioVocabSize * config.hiddenSize
        )

        if config.usesSpeakerEmbedding, archive.contains("xvec_w") {
            self.xvecWeight = try archive.floatArray(
                named: "xvec_w",
                expectedCount: config.hiddenSize * config.speakerEmbeddingDimension
            )
            self.xvecBias = try archive.floatArray(named: "xvec_b", expectedCount: config.hiddenSize)
            self.xvecLayerNormWeight = try archive.floatArray(named: "xvec_ln_w", expectedCount: config.hiddenSize)
            self.xvecLayerNormBias = try archive.floatArray(named: "xvec_ln_b", expectedCount: config.hiddenSize)
            self.xvecLayerNormEpsilon = (try? archive.scalar(named: "xvec_ln_eps")) ?? 1e-5
        } else {
            self.xvecWeight = nil
            self.xvecBias = nil
            self.xvecLayerNormWeight = nil
            self.xvecLayerNormBias = nil
            self.xvecLayerNormEpsilon = 1e-5
            if config.usesSpeakerEmbedding {
                AppLogger.shared.log("🗣️ [VieNeuEmbeddingTables] config bật use_speaker_embedding nhưng npz thiếu xvec_* — giọng sẽ sai")
            }
        }
    }

    // MARK: - Speaker anchor

    /// x-vector 192 chiều → vector `hiddenSize` cộng vào **mọi** hàng prompt.
    ///
    /// Đúng thứ tự của model: `Linear` rồi `LayerNorm`. LayerNorm dùng phương sai **toàn phần**
    /// (chia `n`, không phải `n-1`) để khớp `np.var` mặc định — dùng phương sai mẫu sẽ lệch nhẹ
    /// theo hướng rất khó phát hiện bằng tai.
    func speakerAnchor(for embedding: [Float]) throws -> [Float] {
        guard let weight = xvecWeight,
              let bias = xvecBias,
              let normWeight = xvecLayerNormWeight,
              let normBias = xvecLayerNormBias else {
            throw TTSError.internalError("npz thiếu xvec_* nên không dựng được speaker anchor")
        }
        guard embedding.count == config.speakerEmbeddingDimension else {
            throw TTSError.internalError(
                "speaker_emb có \(embedding.count) chiều, cần \(config.speakerEmbeddingDimension)"
            )
        }

        let hidden = config.hiddenSize
        var projected = [Float](repeating: 0, count: hidden)

        // xvec_w là (hidden, spkDim) row-major, cần projected[i] = Σ_j w[i][j] * emb[j] ⇒ NoTrans.
        weight.withUnsafeBufferPointer { weightBuffer in
            embedding.withUnsafeBufferPointer { embeddingBuffer in
                guard let weightBase = weightBuffer.baseAddress,
                      let embeddingBase = embeddingBuffer.baseAddress else { return }
                cblas_sgemv(
                    CblasRowMajor, CblasNoTrans,
                    Int32(hidden), Int32(config.speakerEmbeddingDimension),
                    1.0, weightBase, Int32(config.speakerEmbeddingDimension),
                    embeddingBase, 1,
                    0.0, &projected, 1
                )
            }
        }
        for index in 0..<hidden { projected[index] += bias[index] }

        var mean: Float = 0
        vDSP_meanv(projected, 1, &mean, vDSP_Length(hidden))
        var variance: Float = 0
        for value in projected {
            let delta = value - mean
            variance += delta * delta
        }
        variance /= Float(hidden)
        let inverseStdDev = 1.0 / (variance + xvecLayerNormEpsilon).squareRoot()

        for index in 0..<hidden {
            projected[index] = (projected[index] - mean) * inverseStdDev * normWeight[index] + normBias[index]
        }
        return projected
    }

    // MARK: - Dựng input embedding

    /// Cộng embedding của một hàng prompt vào `destination[offset..<offset+hiddenSize]`.
    ///
    /// Một hàng gồm một token text ở cột 0 và `codebookCount` code audio ở các cột sau; code bằng
    /// `audioPadTokenID` nghĩa là "ô trống", **không** phải index hợp lệ vào bảng.
    func writeRowEmbedding(
        textToken: Int,
        audioCodes: ArraySlice<Int32>?,
        anchor: [Float]?,
        into destination: inout [Float],
        rowOffset: Int
    ) throws {
        let hidden = config.hiddenSize
        guard textToken >= 0 && textToken < config.textVocabSize else {
            throw TTSError.internalError("Token text \(textToken) ngoài khoảng 0..<\(config.textVocabSize)")
        }
        let textOffset = textToken * hidden
        for index in 0..<hidden {
            destination[rowOffset + index] = textEmbedding[textOffset + index]
        }

        if let audioCodes {
            var channel = 0
            for code in audioCodes {
                guard channel < config.codebookCount else { break }
                defer { channel += 1 }
                if Int(code) == config.audioPadTokenID { continue }
                guard code >= 0 && Int(code) < config.audioVocabSize else {
                    throw TTSError.internalError("Code audio \(code) ngoài khoảng 0..<\(config.audioVocabSize)")
                }
                let base = (channel * config.audioVocabSize + Int(code)) * hidden
                audioEmbedding.withUnsafeBufferPointer { buffer in
                    guard let source = buffer.baseAddress else { return }
                    destination.withUnsafeMutableBufferPointer { output in
                        guard let target = output.baseAddress else { return }
                        // out += emb (một lời gọi thay cho 768 phép cộng có bounds-check).
                        cblas_saxpy(Int32(hidden), 1.0, source + base, 1, target + rowOffset, 1)
                    }
                }
            }
        }

        if let anchor, anchor.count == hidden {
            anchor.withUnsafeBufferPointer { buffer in
                guard let source = buffer.baseAddress else { return }
                destination.withUnsafeMutableBufferPointer { output in
                    guard let target = output.baseAddress else { return }
                    cblas_saxpy(Int32(hidden), 1.0, source, 1, target + rowOffset, 1)
                }
            }
        }
    }

    /// Embedding của **một** code ở codebook `channel` — dùng làm input cho bước acoustic kế tiếp.
    func audioCodeEmbedding(channel: Int, code: Int32, into destination: inout [Float]) throws {
        let hidden = config.hiddenSize
        guard channel >= 0 && channel < config.codebookCount else {
            throw TTSError.internalError("Codebook \(channel) ngoài khoảng 0..<\(config.codebookCount)")
        }
        guard code >= 0 && Int(code) < config.audioVocabSize else {
            throw TTSError.internalError("Code audio \(code) ngoài khoảng 0..<\(config.audioVocabSize)")
        }
        let base = (channel * config.audioVocabSize + Int(code)) * hidden
        for index in 0..<hidden {
            destination[index] = audioEmbedding[base + index]
        }
    }

    func textTokenEmbedding(_ token: Int, into destination: inout [Float], offset: Int = 0) throws {
        guard token >= 0 && token < config.textVocabSize else {
            throw TTSError.internalError("Token text \(token) ngoài khoảng 0..<\(config.textVocabSize)")
        }
        let base = token * config.hiddenSize
        for index in 0..<config.hiddenSize {
            destination[offset + index] = textEmbedding[base + index]
        }
    }

    // MARK: - Logits (bảng tied dùng làm ma trận đầu ra)

    /// `hidden @ audio_emb[channel].T` → `logits` (1024 phần tử).
    func audioLogits(channel: Int, hidden: [Float], into logits: inout [Float]) {
        let hiddenSize = config.hiddenSize
        let vocab = config.audioVocabSize
        let base = channel * vocab * hiddenSize
        audioEmbedding.withUnsafeBufferPointer { tableBuffer in
            hidden.withUnsafeBufferPointer { hiddenBuffer in
                guard let tableBase = tableBuffer.baseAddress,
                      let hiddenBase = hiddenBuffer.baseAddress else { return }
                cblas_sgemv(
                    CblasRowMajor, CblasNoTrans,
                    Int32(vocab), Int32(hiddenSize),
                    1.0, tableBase + base, Int32(hiddenSize),
                    hiddenBase, 1,
                    0.0, &logits, 1
                )
            }
        }
    }

    /// `hidden @ text_emb.T` → argmax. Chỉ cần chỉ số lớn nhất để phát hiện token kết thúc tiếng nói.
    func textLogitsArgmax(hidden: [Float], scratch: inout [Float]) -> Int {
        let hiddenSize = config.hiddenSize
        let vocab = config.textVocabSize
        textEmbedding.withUnsafeBufferPointer { tableBuffer in
            hidden.withUnsafeBufferPointer { hiddenBuffer in
                guard let tableBase = tableBuffer.baseAddress,
                      let hiddenBase = hiddenBuffer.baseAddress else { return }
                cblas_sgemv(
                    CblasRowMajor, CblasNoTrans,
                    Int32(vocab), Int32(hiddenSize),
                    1.0, tableBase, Int32(hiddenSize),
                    hiddenBase, 1,
                    0.0, &scratch, 1
                )
            }
        }
        var peak: Float = 0
        var index: vDSP_Length = 0
        vDSP_maxvi(scratch, 1, &peak, &index, vDSP_Length(vocab))
        return Int(index)
    }
}
