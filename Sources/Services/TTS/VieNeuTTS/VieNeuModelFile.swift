import Foundation

/// Từng file trong bộ model VieNeu-TTS v3 Turbo.
///
/// **Tên file là hợp đồng với ONNX Runtime, không phải chuyện tuỳ ý.**
/// `vieneu_prefill.onnx` và `vieneu_decode_step.onnx` tham chiếu `vieneu_backbone_shared.data`
/// bằng **tên trần** trong external-data proto; ORT phân giải tên đó **tương đối với thư mục chứa
/// file .onnx**. Cùng lý do với `moss_audio_tokenizer_decode_shared.data`. Vì vậy cả bộ phải nằm
/// trong một thư mục và không được đổi tên — khác hẳn `ModelStore` của Piper vốn đặt tên file theo
/// từng giọng.
enum VieNeuModelFile: String, CaseIterable {
    case prefill = "vieneu_prefill.onnx"
    case decodeStep = "vieneu_decode_step.onnx"
    case acoustic = "vieneu_acoustic_cached.onnx"
    case backboneData = "vieneu_backbone_shared.data"
    case heads = "vieneu_v3_heads.npz"
    case config = "config.json"
    case tokenizer = "tokenizer.json"
    case codecDecode = "moss_audio_tokenizer_decode_full.onnx"
    case codecData = "moss_audio_tokenizer_decode_shared.data"
    case seaG2P = "sea_g2p.bin"
    case voices = "voices_v3_turbo.json"

    /// Cỡ tối thiểu hợp lệ (byte).
    ///
    /// Dùng để loại file tải dở **và** trang lỗi mà máy chủ trả về kèm HTTP 200 — thứ mà
    /// `URLSession` không coi là thất bại. Không có chốt này thì một file 2 KB chứa HTML sẽ làm
    /// `ORTSession` chết bằng thông báo chẳng liên quan gì tới nguyên nhân thật, mà trên iPhone
    /// thật thì chỉ có `app_logs.txt` để chẩn đoán.
    var minimumBytes: Int {
        switch self {
        case .backboneData: return 90_000_000
        case .heads: return 20_000_000
        case .codecData: return 40_000_000
        case .seaG2P: return 50_000_000
        case .acoustic: return 5_000_000
        case .prefill, .decodeStep: return 200_000
        case .codecDecode: return 300_000
        case .voices: return 50_000
        case .tokenizer: return 10_000
        case .config: return 500
        }
    }
}
