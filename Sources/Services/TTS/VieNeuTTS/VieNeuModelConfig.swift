import Foundation

/// Cấu hình model đọc từ `config.json` của bộ `onnx_int8`.
///
/// Chỉ giữ những trường mà đường suy luận thật sự cần. Mọi giá trị đều **đọc từ file**, không
/// hardcode, vì bộ `onnx_int8` khác bộ `onnx` ở đúng những con số này (`localHiddenLayers` 1 vs 2,
/// `usesSpeakerEmbedding` true vs false) và hardcode là cách chắc chắn nhất để crash khi đổi bộ.
struct VieNeuModelConfig: Sendable {
    let hiddenSize: Int
    let numHiddenLayers: Int
    let localHiddenLayers: Int
    let localAttentionHeads: Int
    let codebookCount: Int
    let audioVocabSize: Int
    let audioPadTokenID: Int
    let textVocabSize: Int
    let textPromptStartTokenID: Int
    let textPromptEndTokenID: Int
    let speechGenerationStartTokenID: Int
    let speechGenerationEndTokenID: Int
    let audioReferenceSlotTokenID: Int
    /// Token dẫn đầu prompt.
    ///
    /// **Luôn dùng giá trị này (16), không bao giờ dùng `tin_tuc` (17) hay `doc_truyen` (18).**
    /// `config.json` khai `reserved_token_start = 13` và `num_reserved_tokens = 30`, nên id 13..42 là
    /// ô dự trữ khởi tạo **random và chưa được train** — hai nhãn phong cách kia nằm trong vùng đó.
    /// Engine tham chiếu cũng ép cứng về giá trị này và bỏ qua tham số `style`.
    let defaultStyleTokenID: Int
    let usesSpeakerEmbedding: Bool
    let speakerEmbeddingDimension: Int
    let audioSampleRate: Int
    let maxPositionEmbeddings: Int

    /// Chiều của mỗi head ở acoustic decoder — dùng để dựng tensor KV rỗng ban đầu.
    var localHeadDimension: Int { hiddenSize / max(1, localAttentionHeads) }

    private struct Raw: Decodable {
        let hidden_size: Int?
        let num_hidden_layers: Int?
        let local_num_hidden_layers: Int?
        let local_num_attention_heads: Int?
        let n_vq: Int?
        let audio_vocab_size: Int?
        let audio_pad_token_id: Int?
        let text_vocab_size: Int?
        let text_prompt_start_token_id: Int?
        let text_prompt_end_token_id: Int?
        let speech_generation_start_token_id: Int?
        let speech_generation_end_token_id: Int?
        let audio_ref_slot_token_id: Int?
        let default_style_token_id: Int?
        let use_speaker_embedding: Bool?
        let speaker_embedding_dim: Int?
        let audio_sample_rate: Int?
        let max_position_embeddings: Int?
    }

    init(url: URL) throws {
        let raw = try JSONDecoder().decode(Raw.self, from: try Data(contentsOf: url))
        hiddenSize = raw.hidden_size ?? 768
        numHiddenLayers = raw.num_hidden_layers ?? 12
        localHiddenLayers = raw.local_num_hidden_layers ?? 1
        localAttentionHeads = raw.local_num_attention_heads ?? 8
        codebookCount = raw.n_vq ?? 16
        audioVocabSize = raw.audio_vocab_size ?? 1024
        audioPadTokenID = raw.audio_pad_token_id ?? 1024
        textVocabSize = raw.text_vocab_size ?? 419
        textPromptStartTokenID = raw.text_prompt_start_token_id ?? 3
        textPromptEndTokenID = raw.text_prompt_end_token_id ?? 4
        speechGenerationStartTokenID = raw.speech_generation_start_token_id ?? 5
        speechGenerationEndTokenID = raw.speech_generation_end_token_id ?? 6
        audioReferenceSlotTokenID = raw.audio_ref_slot_token_id ?? 7
        defaultStyleTokenID = raw.default_style_token_id ?? 16
        usesSpeakerEmbedding = raw.use_speaker_embedding ?? false
        speakerEmbeddingDimension = raw.speaker_embedding_dim ?? 192
        audioSampleRate = raw.audio_sample_rate ?? 48_000
        maxPositionEmbeddings = raw.max_position_embeddings ?? 1024
    }
}
