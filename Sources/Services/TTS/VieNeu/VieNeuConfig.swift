import Foundation

/// Cấu hình + hằng số của **VieNeu-TTS v3 Nano**, đọc từ `config.json` và `constants.npz` trên đĩa.
///
/// ## Bẫy 1 — vocab là theo **Unicode scalar**, không theo `Character`
/// `config.json` khai 78 entry một-ký-tự, trong đó có **bốn dấu tổ hợp** `̪` (U+032A), `̩` (U+0329),
/// `̃` (U+0303), `ʲ` (U+02B2). Bản tham chiếu Python duyệt `for ch in s` — tức **từng code point**.
/// Swift thì `for ch in s` duyệt **grapheme cluster**: `"t" + "̪"` ra **một** `Character` `"t̪"`, không
/// khớp được entry `"t"` lẫn entry `"̪"`. Vì vậy toàn bộ phép mã hoá ở đây đi qua `unicodeScalars`, và
/// vocab lưu bằng `[UInt32: Int64]`. Làm sai chỗ này thì phoneme bị **nuốt im lặng** (xem `encode`).
///
/// ## Bẫy 2 — `constants.npz` là ZIP **stored**, không deflate
/// Đã kiểm cả 5 entry: `compress_type = 0` (ZIP_STORED), NPY version 1.0, `descr = '<f4'`. Nên bộ đọc
/// dưới đây đọc thẳng vùng dữ liệu sau header thay vì giải nén — nhưng vẫn **kiểm `compress_type`** và
/// throw nếu gặp entry nén, để một bản `constants.npz` đóng gói lại bằng `savez_compressed` không âm
/// thầm trả về rác.
struct VieNeuConfig: Sendable {
    let sampleRate: Int
    let flowFPS: Double
    /// `dim` của `config.json` = 512 — chiều ẩn của `ctx`. Cần để **suy ra shape tensor theo công thức**
    /// thay vì hỏi ONNX Runtime: shape của `ctx` là `[1, số phoneme, dim]`, và biết trước thì không phải
    /// gọi `tensorTypeAndShapeInfo()` (API dễ lệch giữa các bản ORT) trong đường nóng.
    let dim: Int
    let latentDim: Int
    let group: Int
    let nStyle: Int
    let styleDim: Int
    let bosID: Int64
    let eosID: Int64
    let padID: Int64
    let defaultSteps: Int
    let defaultCFG: Float
    /// `<|emotion_1|>` → `①` … Nano chỉ có 3 tag này.
    let emotionMap: [String: String]
    /// Giá trị scalar → id. Xem bẫy 1 ở doc của type.
    let vocab: [UInt32: Int64]
    let constants: Constants

    /// Chiều dài latent của một frame: `latentDim * group` = 24 × 6 = **144** (shape của `x`).
    var latentChannels: Int { latentDim * group }

    /// Số frame tối thiểu — dưới ngưỡng này `vector_estimator` nhận shape suy biến.
    static let minFrames = 2
    /// Trần độ dài mỗi chunk. Bản tham chiếu cắt `secs = min(exp(log_s)/speed, 15.0)`; dài hơn thì
    /// chất lượng trôi.
    static let maxChunkSeconds = 15.0
    /// Trần ký tự mỗi chunk khi tách văn bản (`normalize_to_chunks_v3_with_gaps(text, max_chars=140)`).
    static let maxChunkCharacters = 140

    /// Hai tensor vô điều kiện cho nhánh CFG, lấy từ `constants.npz`.
    struct Constants: Sendable {
        /// `null_spk.npy` — shape (192,).
        let nullSpeaker: [Float]
        /// `null_style.npy` — shape (50, 256), đã làm phẳng theo hàng.
        let nullStyle: [Float]
    }

    // MARK: - Đọc

    enum LoadError: LocalizedError {
        case unreadable(String)
        case badNPZ(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let name): return "Không đọc được \(name) của VieNeu-TTS"
            case .badNPZ(let reason): return "constants.npz không hợp lệ: \(reason)"
            }
        }
    }

    static func load(modelStore: VieNeuModelStore) throws -> VieNeuConfig {
        let configURL = modelStore.url(for: "config.json")
        guard let data = try? Data(contentsOf: configURL) else {
            throw LoadError.unreadable("config.json")
        }
        let raw = try JSONDecoder().decode(RawConfig.self, from: data)

        var vocab: [UInt32: Int64] = [:]
        for (key, id) in raw.vocab {
            // Chỉ nhận entry một scalar; entry nhiều ký tự duy nhất trong file là emotion tag
            // (`<|emotion_1|>`), và chúng đi qua `emotion_tags` chứ không qua vocab.
            guard key.unicodeScalars.count == 1, let scalar = key.unicodeScalars.first else { continue }
            vocab[scalar.value] = id
        }

        let arrays = try NPZReader.read(url: modelStore.url(for: "constants.npz"))
        guard let nullSpeaker = arrays["null_spk"]?.values else {
            throw LoadError.badNPZ("thiếu null_spk.npy")
        }
        guard let nullStyle = arrays["null_style"]?.values else {
            throw LoadError.badNPZ("thiếu null_style.npy")
        }

        return VieNeuConfig(
            sampleRate: raw.sample_rate,
            flowFPS: raw.flow_fps,
            dim: raw.dim,
            latentDim: raw.latent_dim,
            group: raw.group,
            nStyle: raw.n_style,
            styleDim: raw.style_dim,
            bosID: raw.bos_id,
            eosID: raw.eos_id,
            padID: raw.pad_id,
            defaultSteps: raw.steps_default,
            defaultCFG: raw.cfg_default,
            emotionMap: raw.emotion_tags,
            vocab: vocab,
            constants: Constants(nullSpeaker: nullSpeaker, nullStyle: nullStyle)
        )
    }

    /// `config.json` khai theo snake_case; giữ đúng tên khoá thay vì viết `CodingKeys` để một khoá đổi
    /// tên ở upstream là lỗi decode ồn ào, không phải giá trị mặc định im lặng.
    private struct RawConfig: Decodable {
        let sample_rate: Int
        let flow_fps: Double
        let dim: Int
        let latent_dim: Int
        let group: Int
        let n_style: Int
        let style_dim: Int
        let bos_id: Int64
        let eos_id: Int64
        let pad_id: Int64
        let steps_default: Int
        let cfg_default: Float
        let vocab: [String: Int64]
        let emotion_tags: [String: String]
    }

    // MARK: - Mã hoá phoneme

    /// `bos` + từng scalar có trong vocab + `eos`. Scalar lạ bị **bỏ qua** (đúng hành vi bản tham chiếu,
    /// ở đó OOV bị drop kèm cảnh báo một lần) — nhưng đếm lại để bên gọi ghi log, vì drop im lặng là
    /// kiểu lỗi chỉ nghe ra chứ không thấy được.
    func encode(phonemes: String) -> (ids: [Int64], droppedScalars: Int) {
        var ids: [Int64] = [bosID]
        var dropped = 0
        for scalar in phonemes.unicodeScalars {
            if let id = vocab[scalar.value] {
                ids.append(id)
            } else {
                dropped += 1
            }
        }
        ids.append(eosID)
        return (ids, dropped)
    }

    /// Thay tag cảm xúc (`<|emotion_1|>`) bằng ký tự đơn tương ứng trước khi mã hoá — đúng thứ tự của
    /// `encode_phones` trong bản tham chiếu.
    func applyingEmotionTags(to phonemes: String) -> String {
        guard !emotionMap.isEmpty else { return phonemes }
        var result = phonemes
        for (tag, character) in emotionMap {
            result = result.replacingOccurrences(of: tag, with: character)
        }
        return result
    }
}

