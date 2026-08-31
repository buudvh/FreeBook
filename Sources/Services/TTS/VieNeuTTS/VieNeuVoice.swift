import Foundation

/// Một giọng preset của VieNeu-TTS v3 Turbo.
///
/// Giọng ở model này **không** phải một file model riêng như Piper: nó là một cặp
/// (`speakerEmbedding`, `referenceCodes`) được nhồi vào prompt. `referenceCodes` là ~4 giây audio
/// mẫu đã mã hoá sẵn qua codec MOSS (50 frame × 16 codebook ở 12.5 frame/giây), còn
/// `speakerEmbedding` là x-vector 192 chiều đi qua phép chiếu `xvec_*` rồi cộng vào mọi hàng prompt.
///
/// Vì vậy 20 giọng dùng **chung một** bộ model — đổi giọng không cần tải gì thêm.
struct VieNeuVoice: Identifiable, Sendable {
    let name: String
    let description: String
    let gender: String
    let region: String
    /// Nhãn phong cách trong file dữ liệu. **Chỉ để hiển thị.**
    ///
    /// Không được dịch nhãn này thành style token: `config.json` khai `reserved_token_start = 13`
    /// và `num_reserved_tokens = 30`, nên id 13..42 là ô random-init **chưa train** — trong đó có cả
    /// `tin_tuc` (17) và `doc_truyen` (18). Token dẫn đầu prompt luôn phải là `defaultStyleTokenID`.
    let style: String
    let speakerEmbedding: [Float]
    let referenceCodes: [[Int32]]

    var id: String { name }

    /// Nhãn cho Picker: "Trúc Ly · Nữ · Bắc".
    var displayLabel: String {
        let parts = [name, gender == "male" ? "Nam" : "Nữ", region].filter { !$0.isEmpty }
        return parts.joined(separator: " · ")
    }
}
