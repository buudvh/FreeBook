import Accelerate
import Foundation

/// Bước 3 của LAC: mạng embedding ⇒ 2 lớp BiGRU ⇒ FC ⇒ điểm phát xạ ⇒ Viterbi (`LACViterbi`) ⇒ id nhãn.
///
/// Công thức chép từ `make_forward` của `Tools/lac-export/export_lac.py` (trùng predictor Paddle của LAC 3203 / 3203 câu
/// với fp32, 3201 / 3203 với embedding fp16 như file tải về), từng phép cộng theo đúng thứ tự numpy:
/// - lớp `l`: chiều xuôi `x·fc_{2l}.w + fc_{2l}.b + gru_{2l}.b` → `gru_{2l}`; chiều ngược `fc_{2l+1}` → `gru_{2l+1}`
///   chạy từ cuối câu; ghép [xuôi, ngược] làm đầu vào lớp sau;
/// - GRU: trọng số `[H, 3H]` đọc như **buffer phẳng** — `2H·H` số đầu là `W_gate [H, 2H]`, còn lại `W_state [H, H]`;
///   `g = x[:2H] + h·W_gate`, `u = σ(g[:H])`, `r = σ(g[H:])`, `c = tanh(x[2H:] + (r⊙h)·W_state)`,
///   `h = (1 − u)⊙h + u⊙c`, `h` đầu = 0.
///
/// Trọng số fp32 (~2 MB) chép vào `[Float]` lúc nạp; riêng `word_emb` fp16 (~15 MB) giữ trong `Data` ánh xạ bộ nhớ, đổi
/// sang `Float` khi tra từng hàng. Bất biến ⇒ gọi song song an toàn; mọi bộ đệm cấp theo từng lần `decode`, không cấp
/// phát trong vòng lặp bước.
struct LACNetwork: Sendable {
    private struct Cell: Sendable {
        let inputSize: Int
        /// `fc_k.w` `[inputSize, 3H]`, `fc_k.b` `[3H]`, `gru_k.b` `[3H]`.
        let projection: [Float]
        let projectionBias: [Float]
        let gruBias: [Float]
        /// `W_gate` `[H, 2H]` và `W_state` `[H, H]` cắt từ buffer phẳng `gru_k.w`.
        let gate: [Float]
        let state: [Float]
    }

    let hidden: Int
    let embeddingDim: Int
    let vocabSize: Int
    let labelCount: Int

    private let weights: Data
    private let embeddingOffset: Int
    /// Thứ tự: lớp 0 xuôi, lớp 0 ngược, lớp 1 xuôi, lớp 1 ngược.
    private let cells: [Cell]
    private let emissionWeight: [Float]
    private let emissionBias: [Float]
    private let crf: [Float]

    /// `weights` = nội dung `lac_weights.bin` (nên mở bằng `.alwaysMapped`). Ném `invalidFiles` khi tensor sai hình dạng.
    init(weights: Data, manifest: LACManifest) throws {
        let network = manifest.network
        let hidden = network.hiddenSize
        let embeddingDim = network.embeddingDim
        let labels = network.numLabels

        func tensor(_ name: String, dtype: String = "float32", shape: [Int]) throws -> LACManifest.Tensor {
            guard let found = manifest.tensor(name), found.dtype == dtype,
                  found.shape.reduce(1, *) == shape.reduce(1, *),
                  found.offset + found.bytes <= weights.count else {
                throw LACModelError.invalidFiles("\(LACModelMirror.weightsName): \(name) sai hình dạng")
            }
            return found
        }
        func floats(_ name: String, shape: [Int]) throws -> [Float] {
            let info = try tensor(name, shape: shape)
            var values = [Float](repeating: 0, count: info.bytes / 4)
            let start = weights.startIndex + info.offset
            values.withUnsafeMutableBufferPointer { buffer in
                _ = weights.copyBytes(to: buffer, from: start..<(start + info.bytes))
            }
            return values
        }

        let embedding = try tensor("word_emb", dtype: "float16", shape: [network.vocabSize, embeddingDim])
        guard embedding.shape == [network.vocabSize, embeddingDim] else {
            throw LACModelError.invalidFiles("\(LACModelMirror.weightsName): word_emb sai hình dạng")
        }
        var cells: [Cell] = []
        for index in 0..<4 {
            let inputSize = index < 2 ? embeddingDim : 2 * hidden
            let flat = try floats("gru_\(index).w_0", shape: [hidden, 3 * hidden])
            let gateCount = 2 * hidden * hidden
            cells.append(Cell(
                inputSize: inputSize,
                projection: try floats("fc_\(index).w_0", shape: [inputSize, 3 * hidden]),
                projectionBias: try floats("fc_\(index).b_0", shape: [3 * hidden]),
                gruBias: try floats("gru_\(index).b_0", shape: [1, 3 * hidden]),
                gate: Array(flat[0..<gateCount]),
                state: Array(flat[gateCount...])
            ))
        }
        self.hidden = hidden
        self.embeddingDim = embeddingDim
        vocabSize = network.vocabSize
        labelCount = labels
        self.weights = weights
        embeddingOffset = embedding.offset
        self.cells = cells
        emissionWeight = try floats("fc_4.w_0", shape: [2 * hidden, labels])
        emissionBias = try floats("fc_4.b_0", shape: [labels])
        crf = try floats("crfw", shape: [labels + 2, labels])
    }

    /// Id nhãn cho từng id đầu vào (cùng độ dài). Id ngoài bảng (không xảy ra — `LACVocabulary` đã kiểm) ⇒ hàng 0.
    func decode(_ ids: [Int32]) -> [Int] {
        let steps = ids.count
        guard steps > 0 else { return [] }
        let width = 3 * hidden
        let pair = 2 * hidden
        let scratchCount = 10 * hidden
        let total = steps * embeddingDim + steps * width + 2 * steps * pair + steps * labelCount + scratchCount
        let workspace = UnsafeMutablePointer<Float>.allocate(capacity: total)
        workspace.initialize(repeating: 0, count: total)
        defer { workspace.deallocate() }

        let input = workspace
        let projected = input + steps * embeddingDim
        let firstLayer = projected + steps * width
        let secondLayer = firstLayer + steps * pair
        let emissions = secondLayer + steps * pair
        let scratch = emissions + steps * labelCount

        gatherEmbeddings(ids, into: input)
        for (index, cell) in cells.enumerated() {
            let source = index < 2 ? UnsafePointer(input) : UnsafePointer(firstLayer)
            let target = index < 2 ? firstLayer : secondLayer
            project(source, steps: steps, cell: cell, into: projected)
            runGRU(projected, steps: steps, cell: cell, reverse: index % 2 == 1,
                   output: target + (index % 2) * hidden, scratch: scratch)
        }
        vDSP_mmul(secondLayer, 1, emissionWeight, 1, emissions, 1,
                  vDSP_Length(steps), vDSP_Length(labelCount), vDSP_Length(pair))
        for step in 0..<steps {
            let row = emissions + step * labelCount
            vDSP_vadd(row, 1, emissionBias, 1, row, 1, vDSP_Length(labelCount))
        }
        return LACViterbi.decode(emissions: emissions, steps: steps, labels: labelCount, crf: crf)
    }

    /// Hàng embedding fp16 ⇒ `Float` (đổi chính xác như `astype(float32)` của numpy).
    private func gatherEmbeddings(_ ids: [Int32], into output: UnsafeMutablePointer<Float>) {
        let rowBytes = embeddingDim * 2
        weights.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            for (step, id) in ids.enumerated() {
                let row = (id >= 0 && Int(id) < vocabSize) ? Int(id) : 0
                let start = embeddingOffset + row * rowBytes
                let destination = output + step * embeddingDim
                for column in 0..<embeddingDim {
                    let bits = raw.loadUnaligned(fromByteOffset: start + column * 2, as: UInt16.self)
                    destination[column] = Float(Float16(bitPattern: UInt16(littleEndian: bits)))
                }
            }
        }
    }

    /// Chiếu cả câu một lần: `out = x·W`, rồi `+ fc.b`, rồi `+ gru.b` (hai phép cộng tách như numpy).
    private func project(
        _ input: UnsafePointer<Float>,
        steps: Int,
        cell: Cell,
        into output: UnsafeMutablePointer<Float>
    ) {
        let width = 3 * hidden
        vDSP_mmul(input, 1, cell.projection, 1, output, 1,
                  vDSP_Length(steps), vDSP_Length(width), vDSP_Length(cell.inputSize))
        for step in 0..<steps {
            let row = output + step * width
            vDSP_vadd(row, 1, cell.projectionBias, 1, row, 1, vDSP_Length(width))
            vDSP_vadd(row, 1, cell.gruBias, 1, row, 1, vDSP_Length(width))
        }
    }

    /// Một chiều GRU; ghi `h` từng bước vào `output + t·2H` (cột 0 chiều xuôi, cột H chiều ngược).
    private func runGRU(
        _ projected: UnsafePointer<Float>,
        steps: Int,
        cell: Cell,
        reverse: Bool,
        output: UnsafeMutablePointer<Float>,
        scratch: UnsafeMutablePointer<Float>
    ) {
        let size = hidden
        let gateWidth = 2 * hidden
        let width = 3 * hidden
        let rowStride = 2 * hidden
        // scratch (10H): h · g · −g · σ(g) (2H mỗi phần) · r⊙h · (r⊙h)·W_state · c
        let state = scratch
        let gates = state + size
        let negated = gates + gateWidth
        let sigmoid = negated + gateWidth
        let resetState = sigmoid + gateWidth
        let candidateInput = resetState + size
        let candidate = candidateInput + size
        state.initialize(repeating: 0, count: size)

        var gateCount = Int32(gateWidth)
        var hiddenCount = Int32(size)
        var one: Float = 1
        for step in 0..<steps {
            let time = reverse ? steps - 1 - step : step
            let input = projected + time * width
            // g = h·W_gate + x[:2H]
            vDSP_mmul(state, 1, cell.gate, 1, gates, 1, 1, vDSP_Length(gateWidth), vDSP_Length(size))
            vDSP_vadd(gates, 1, input, 1, gates, 1, vDSP_Length(gateWidth))
            // σ(g) = 1 / (1 + exp(−g))
            vDSP_vneg(gates, 1, negated, 1, vDSP_Length(gateWidth))
            vvexpf(sigmoid, negated, &gateCount)
            vDSP_vsadd(sigmoid, 1, &one, sigmoid, 1, vDSP_Length(gateWidth))
            vDSP_svdiv(&one, sigmoid, 1, sigmoid, 1, vDSP_Length(gateWidth))
            let update = sigmoid
            let reset = sigmoid + size
            // c = tanh(x[2H:] + (r⊙h)·W_state)
            vDSP_vmul(reset, 1, state, 1, resetState, 1, vDSP_Length(size))
            vDSP_mmul(resetState, 1, cell.state, 1, candidateInput, 1, 1, vDSP_Length(size), vDSP_Length(size))
            vDSP_vadd(candidateInput, 1, input + gateWidth, 1, candidateInput, 1, vDSP_Length(size))
            vvtanhf(candidate, candidateInput, &hiddenCount)
            // h = (1 − u)⊙h + u⊙c
            let row = output + time * rowStride
            for index in 0..<size {
                let value = (1 - update[index]) * state[index] + update[index] * candidate[index]
                state[index] = value
                row[index] = value
            }
        }
    }
}
