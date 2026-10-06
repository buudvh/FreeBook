import Foundation

/// `config.json` của kho weights Kokoro-Vietnamese.
///
/// Chỉ giữ những trường mà **runtime cần**: `vocab` để đổi âm vị thành id, `style_dim` để kiểm shape
/// voicepack, `max_dur` để biết trần độ dài. Hai khối `istftnet` và `plbert` trong file là mô tả kiến trúc —
/// không dùng khi chỉ chạy graph ONNX đã export.
struct KokoroConfig: Decodable {
    /// Số âm vị tối đa trong một lượt — trần cứng của graph (`context_length` trong `onnx_utils.py`).
    static let contextLength = 512
    /// Kokoro-Vietnamese phát ra 24 kHz.
    static let sampleRate = 24_000
    /// Số hàng của voicepack: `ref_s` chọn theo **số âm vị**, và bảng có đúng ngần này hàng.
    static let maxPhonemes = 510
    /// Bề rộng một vector `ref_s` (`[1, 256]`). Bằng `style_dim × 2`.
    static let styleWidth = 256

    let nToken: Int
    let styleDim: Int
    let maxDur: Int
    /// Âm vị và dấu câu → id.
    ///
    /// **Có dấu câu** (`; : , . ! ? — … " ( )`) — khác hẳn MMS-TTS-vie (vocab cấp ký tự, không có dấu câu nào),
    /// nên Kokoro có chỗ ngắt nghỉ tự nhiên.
    let vocab: [String: Int]

    enum ConfigError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return "Không đọc được `config.json` của Kokoro: \(detail)"
            }
        }
    }

    static func load(from url: URL) throws -> KokoroConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let config = try decoder.decode(KokoroConfig.self, from: data)
            guard config.nToken > 0, config.styleDim > 0, !config.vocab.isEmpty else {
                throw ConfigError.unreadable("thiếu trường bắt buộc")
            }
            guard config.styleDim * 2 == KokoroConfig.styleWidth else {
                throw ConfigError.unreadable(
                    "`style_dim` = \(config.styleDim), nhưng `ref_s` khai bề rộng \(KokoroConfig.styleWidth)")
            }
            return config
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
    }

    /// Chuỗi âm vị → id. Ký tự không có trong vocab bị **bỏ qua**, đúng `phonemes_to_input_ids` của bản
    /// tham chiếu.
    ///
    /// **Duyệt theo `unicodeScalars`, không theo `Character`.** Bản tham chiếu duyệt từng **code point**
    /// (`for p in phonemes` của Python), và vocab có những mục là **dấu tổ hợp đứng riêng** (`"̃"` = 17,
    /// `"ː"` = 158, `"ʰ"` = 162, `"ʲ"` = 164). Duyệt theo `Character` sẽ gộp `t` + dấu thành một phần tử và
    /// tra vocab trượt — mất âm mà không báo lỗi.
    func encode(phonemes: String) -> [Int64] {
        var ids: [Int64] = []
        ids.reserveCapacity(phonemes.unicodeScalars.count + 2)
        for scalar in phonemes.unicodeScalars {
            if let id = vocab[String(scalar)] { ids.append(Int64(id)) }
        }
        return ids
    }
}
