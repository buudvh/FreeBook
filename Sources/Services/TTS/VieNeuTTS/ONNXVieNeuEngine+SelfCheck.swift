import Foundation

/// Tự kiểm số học của đường suy luận VieNeu, so với **giá trị tham chiếu đã đo** từ engine Python
/// chạy trên đúng bộ `onnx_int8` này.
///
/// Lý do tồn tại: trên máy thật không có debugger, và "âm thanh ra nhiễu" có thể sinh ra ở bất kỳ
/// tầng nào — G2P, tokenizer, bảng embedding, speaker anchor, vòng acoustic, hay codec. Bộ tự kiểm
/// này **bỏ G2P ra ngoài** (dùng chuỗi phoneme cố định) và in ra bốn mốc số học để bisect bằng đúng
/// **một** lần chạy trên thiết bị:
///
/// | Mốc | Khớp ⇒ | Lệch ⇒ |
/// |---|---|---|
/// | `anchor[0..3]` | `xvec_*` + LayerNorm đúng | lỗi ở `speakerAnchor` hoặc npz |
/// | `embRow0[0..3]` | bảng text_emb + anchor đúng | lỗi ở `writeRowEmbedding` |
/// | `rows` | dựng prompt đúng | lỗi ở `buildPrompt` hoặc tokenizer |
/// | `codes` frame 0 | **cả** prefill + acoustic + heads + argmax đúng | lỗi trong `VieNeuDecodeLoop` |
///
/// Nếu cả bốn khớp mà audio vẫn nhiễu thì lỗi nằm ở codec/hậu xử lý, không phải ở phần sinh code.
///
/// Chạy một lần cho mỗi lần nạp runtime, tốn ~1 frame (≈20 ms). Tắt bằng
/// `UserDefaults.standard.set(false, forKey: ONNXVieNeuEngine.selfCheckEnabledKey)`.
extension ONNXVieNeuEngine {
    static let selfCheckEnabledKey = "vieneuSelfCheckEnabled"

    /// Giọng và chuỗi phoneme dùng cho phép so — phải giữ **nguyên văn**, đổi một ký tự là mọi giá
    /// trị tham chiếu dưới đây vô nghĩa.
    private static let selfCheckVoiceName = "Ngọc Huyền"
    private static let selfCheckPhonemes = "nˌeɜw ɲˌy t̪ˈaː kwˈaj ɗˈə2w ɗˈɛm bˈɔ6n hˈaɜn zˈiɛɜt̪ hˈeɜt̪."

    /// Đo trên engine Python (`OnnxV3LiteEngine`, `onnx_int8`, `temperature = 0`), 2026-08-31.
    private static let expectedAnchorPrefix: [Float] = [0.0421206, -0.5250824, 0.0579391, -0.0589930]
    private static let expectedEmbeddingRow0Prefix: [Float] = [0.0194155, -0.4821137, 0.0605789, -0.0685145]
    private static let expectedPromptRowCount = 120
    private static let expectedFirstFrameCodes: [Int32] = [
        482, 194, 670, 241, 909, 406, 417, 626, 171, 334, 923, 273, 870, 689, 272, 49
    ]

    static var isSelfCheckEnabled: Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: selfCheckEnabledKey) != nil else { return true }
        return defaults.bool(forKey: selfCheckEnabledKey)
    }

    /// In bốn mốc số học kèm mức lệch so với tham chiếu. Không bao giờ throw ra ngoài: đây là chẩn
    /// đoán, hỏng thì chỉ mất log chứ không được làm chết đường phát.
    func runSelfCheck(runtime: Runtime) {
        guard Self.isSelfCheckEnabled else { return }
        do {
            guard let voice = runtime.catalog.voice(named: Self.selfCheckVoiceName) else {
                AppLogger.shared.log(
                    "🗣️ [VieNeuSelfCheck] Bỏ qua: không có giọng '\(Self.selfCheckVoiceName)'. Có: \(runtime.catalog.voices.map(\.name).joined(separator: ", "))"
                )
                return
            }

            let anchor = try resolveAnchor(for: voice, runtime: runtime)
            let phonemeIDs = runtime.tokenizer.encode(text: Self.selfCheckPhonemes)
            let (embeddings, rowCount) = try buildPrompt(
                phonemeIDs: phonemeIDs,
                voice: voice,
                anchor: anchor,
                runtime: runtime
            )

            var parameters = VieNeuDecodeLoop.Parameters()
            parameters.temperature = 0          // greedy ⇒ tất định, mới so được với Python
            parameters.repetitionPenalty = 1.0  // penalty làm lệch argmax
            parameters.maxFrames = 1

            var profile = VieNeuDecodeLoop.Profile()
            let frames = try runtime.decodeLoop.generate(
                promptEmbeddings: embeddings,
                promptRowCount: rowCount,
                anchor: anchor,
                parameters: parameters,
                profile: &profile
            )

            let anchorReport = Self.compare(
                anchor ?? [],
                expected: Self.expectedAnchorPrefix,
                label: "anchor"
            )
            let embeddingReport = Self.compare(
                Array(embeddings.prefix(Self.expectedEmbeddingRow0Prefix.count)),
                expected: Self.expectedEmbeddingRow0Prefix,
                label: "embRow0"
            )
            let codes = frames.first ?? []
            let codesMatch = codes == Self.expectedFirstFrameCodes
            let mismatchCount = zip(codes, Self.expectedFirstFrameCodes).filter { $0 != $1 }.count

            AppLogger.shared.log(
                """
                🗣️ [VieNeuSelfCheck] voice='\(voice.name)' refFrames=\(voice.referenceCodes.count) \
                phonemeIDs=\(phonemeIDs.count) rows=\(rowCount)/\(Self.expectedPromptRowCount)\
                \(rowCount == Self.expectedPromptRowCount ? "" : " ⚠️LỆCH")
                \(anchorReport)
                \(embeddingReport)
                codes=\(codes) \(codesMatch ? "KHỚP ✅" : "LỆCH ⚠️ (\(mismatchCount)/\(Self.expectedFirstFrameCodes.count) kênh khác)")
                expected=\(Self.expectedFirstFrameCodes)
                """
            )
        } catch {
            AppLogger.shared.log("🗣️ [VieNeuSelfCheck] Lỗi: \(error.localizedDescription)")
        }
    }

    /// So `expected.count` phần tử đầu, in mức lệch tuyệt đối lớn nhất.
    ///
    /// Ngưỡng 1e-3 rộng có chủ ý: bảng là fp32 nhưng backbone là int8 và Accelerate có thể dồn tổng
    /// theo thứ tự khác NumPy, nên lệch ~1e-5 là bình thường. Lệch ≥ 1e-3 là sai thuật toán, không
    /// phải sai số làm tròn.
    private static func compare(_ actual: [Float], expected: [Float], label: String) -> String {
        guard actual.count >= expected.count else {
            return "\(label)=⚠️THIẾU (\(actual.count)/\(expected.count) phần tử)"
        }
        var maxDelta: Float = 0
        for index in expected.indices {
            maxDelta = max(maxDelta, abs(actual[index] - expected[index]))
        }
        let head = expected.indices.map { String(format: "%.5f", actual[$0]) }.joined(separator: ", ")
        let verdict = maxDelta < 1e-3 ? "KHỚP ✅" : "LỆCH ⚠️"
        return "\(label)=[\(head)] maxΔ=\(String(format: "%.2e", maxDelta)) \(verdict)"
    }
}
