import Foundation

/// `config.json` của kho weights ZeroTTS, kèm bộ tham số sinh mặc định.
///
/// Ba giá trị ở đây (`dModel`, `nHeads`, `nLayers`, `numCodebooks`, `codebookSize`) **không** được dùng
/// để dựng shape tensor: `ZeroTTSORTCreate` đọc shape thật từ chính graph và trả về `ZeroTTSORTShapes`.
/// Config chỉ dùng để **đối chiếu** và để biết những thứ graph không khai (số giọng, tần số codec, tốc
/// độ lấy mẫu). Đây đúng bài học đã trả giá ở engine VieNeu: dựng shape từ config rồi model báo
/// `Got: 512 Expected: 256`.
struct ZeroTTSConfig: Decodable {
    /// Bộ tham số sinh — mặc định lấy nguyên từ `DEFAULT_SAMPLING` của bản port JS.
    struct Sampling {
        var cfgScale: Float = 1.0
        var textTemperature: Float = 1.0
        var textTopK: Int = 50
        var audioTemperature: Float = 0.8
        var audioTopK: Int = 25
        var audioTopP: Float = 0.95
        var audioRepetitionPenalty: Float = 1.2
        var minFrames: Int = 4
        /// Trần số frame audio.
        ///
        /// Upstream để **1500** (2 phút audio) vì nó phục vụ cả văn bản dài. Màn thử của spike chỉ đọc
        /// một đoạn ngắn nên hạ xuống **500** (40 giây): `packed_kv` được cấp trước theo trần này, và ở
        /// 1500 thì riêng KV đã ~83 MB. Đây là **lệch có chủ ý** so với tham chiếu, không phải mặc định
        /// của model.
        var maxFrames: Int = 500
        var eoaExtraFrames: Int = 1
    }

    let vocabSize: Int
    let numCodebooks: Int
    let codebookSize: Int
    let dModel: Int
    let nHeads: Int
    let nLayers: Int
    let nVoiceQueries: Int
    let sampleRate: Int
    let codecFrameRate: Double

    /// Chiều mỗi head. `cross_kv`/`packed_kv` khai `(…, n_heads, …, d_head)` nên hai số này phải khớp
    /// `d_model = n_heads × d_head`; lệch nghĩa là config không thuộc bộ weights này.
    var headDim: Int { max(1, dModel / max(1, nHeads)) }

    /// Số giây audio trên một frame. `codec_frame_rate` = 12.5 ⇒ 80 ms.
    var secondsPerFrame: Double { codecFrameRate > 0 ? 1.0 / codecFrameRate : 0.08 }

    enum ConfigError: LocalizedError {
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .unreadable(let detail): return "Không đọc được `config.json` của ZeroTTS: \(detail)"
            }
        }
    }

    static func load(from url: URL) throws -> ZeroTTSConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        // `config.json` dùng snake_case (`d_model`, `n_voice_queries`, …). Khoá lạ (`text_format`,
        // `special_tokens`) bị bỏ qua — `Decodable` không đòi khai hết.
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            let config = try decoder.decode(ZeroTTSConfig.self, from: data)
            guard config.dModel > 0, config.nHeads > 0, config.numCodebooks > 0 else {
                throw ConfigError.unreadable("thiếu chiều bắt buộc")
            }
            return config
        } catch let error as ConfigError {
            throw error
        } catch {
            throw ConfigError.unreadable(error.localizedDescription)
        }
    }
}
