import Foundation
import OnnxRuntimeBindings

/// Tên input/output của một graph tự hồi quy, **phát hiện từ chính session** thay vì viết cứng.
///
/// Lý do bắt buộc: bộ `onnx_int8` khai `local_num_hidden_layers = 1` còn bộ `onnx` (fp32, cũ hơn)
/// dùng 2 layer. Bản thử nghiệm viết cứng `past_k_0` + `past_k_1` nên chỉ cần đổi sang bộ int8 là
/// session từ chối feed. Đọc `inputNames()` một lần lúc nạp là cách duy nhất để cùng một đoạn mã
/// chạy được với cả hai bộ, và để lần đổi bộ tiếp theo không thành một vòng CI 15 phút nữa.
struct VieNeuSessionLayout {
    /// `past_k_0`, `past_k_1`, … theo đúng thứ tự chỉ số.
    let pastKeyNames: [String]
    let pastValueNames: [String]
    /// `present_k_0`, … theo đúng thứ tự chỉ số.
    let presentKeyNames: [String]
    let presentValueNames: [String]
    /// Output hidden state — output duy nhất không phải KV cache.
    let hiddenOutputName: String
    /// Input nhận embedding (`inputs_embeds` ở prefill/decode, `token_emb` ở acoustic).
    let embeddingInputName: String
    /// Input `position_ids`, nếu graph có.
    let positionInputName: String?
    /// Toàn bộ output name, để truyền vào `run(withInputs:outputNames:)`.
    let allOutputNames: Set<String>

    var layerCount: Int { pastKeyNames.count }

    init(session: ORTSession, label: String) throws {
        let inputNames = try session.inputNames()
        let outputNames = try session.outputNames()

        pastKeyNames = Self.ordered(inputNames, prefix: "past_k_")
        pastValueNames = Self.ordered(inputNames, prefix: "past_v_")
        presentKeyNames = Self.ordered(outputNames, prefix: "present_k_")
        presentValueNames = Self.ordered(outputNames, prefix: "present_v_")

        guard !presentKeyNames.isEmpty,
              presentKeyNames.count == presentValueNames.count else {
            throw TTSError.internalError("\(label): không tìm thấy cặp present_k/present_v hợp lệ")
        }
        guard pastKeyNames.count == pastValueNames.count else {
            throw TTSError.internalError("\(label): số past_k và past_v lệch nhau")
        }
        // Prefill không có `past_*`; decode/acoustic thì phải khớp số layer với `present_*`.
        guard pastKeyNames.isEmpty || pastKeyNames.count == presentKeyNames.count else {
            throw TTSError.internalError(
                "\(label): \(pastKeyNames.count) layer past nhưng \(presentKeyNames.count) layer present"
            )
        }

        let cacheNames = Set(presentKeyNames + presentValueNames)
        guard let hidden = outputNames.first(where: { !cacheNames.contains($0) }) else {
            throw TTSError.internalError("\(label): không tìm thấy output hidden state")
        }
        hiddenOutputName = hidden
        allOutputNames = Set(outputNames)

        positionInputName = inputNames.first { $0 == "position_ids" }
        let pastInputNames = Set(pastKeyNames + pastValueNames)
        guard let embedding = inputNames.first(where: {
            !pastInputNames.contains($0) && $0 != "position_ids"
        }) else {
            throw TTSError.internalError("\(label): không tìm thấy input nhận embedding")
        }
        embeddingInputName = embedding
    }

    /// Lọc theo tiền tố rồi sắp theo **số** ở đuôi. Không dùng thứ tự mà `outputNames()` trả về:
    /// nó là thứ tự băm nên `present_k_10` có thể đứng trước `present_k_2`, và feed lệch layer sẽ
    /// tạo ra âm thanh sai mà không có lỗi nào được ném ra.
    private static func ordered(_ names: [String], prefix: String) -> [String] {
        names
            .compactMap { name -> (Int, String)? in
                guard name.hasPrefix(prefix), let index = Int(name.dropFirst(prefix.count)) else { return nil }
                return (index, name)
            }
            .sorted { $0.0 < $1.0 }
            .map(\.1)
    }
}
