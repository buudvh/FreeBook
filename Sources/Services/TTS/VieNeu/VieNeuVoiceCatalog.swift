import Foundation

/// Danh sách giọng preset của **VieNeu-TTS v3 Nano**, đọc từ `voices_v3_nano.json`.
///
/// Mỗi giọng chỉ là **hai mảng số** — không có file model riêng: `speaker_emb` (192-d x-vector) và
/// `style` (50 × 256 style token). Vì vậy "tải model" của engine này là tải **một** bộ graph dùng chung
/// cho cả 11 giọng, khác hẳn Piper (mỗi giọng một file `.onnx`).
///
/// **Thứ tự hiển thị không giữ được như file gốc.** `presets` là một object JSON; `JSONDecoder` trả về
/// `Dictionary` nên thứ tự khoá mất. Thay vì để thứ tự ngẫu nhiên theo hash, catalog xếp **giọng mặc
/// định lên đầu**, phần còn lại theo alphabet — xác định giữa các lần chạy.
struct VieNeuVoiceCatalog: Sendable {
    struct Preset: Sendable {
        let voice: Voice
        let gender: String
        let summary: String
        /// 192 phần tử.
        let speakerEmbedding: [Float]
        /// 50 × 256 = 12.800 phần tử, đã làm phẳng theo hàng.
        let style: [Float]
    }

    let presets: [Preset]
    let defaultVoiceName: String

    /// Kích thước đã xác minh từ `voices_v3_nano.json` thật (2,3 MB, 11 giọng).
    static let speakerEmbeddingCount = 192
    static let styleRows = 50
    static let styleColumns = 256
    static var styleCount: Int { styleRows * styleColumns }

    var defaultPreset: Preset? {
        presets.first { $0.voice.name == defaultVoiceName } ?? presets.first
    }

    func preset(named name: String) -> Preset? {
        presets.first { $0.voice.name == name }
    }

    func preset(withID id: String) -> Preset? {
        presets.first { $0.voice.id == id }
    }

    // MARK: - Đọc

    enum LoadError: LocalizedError {
        case unreadable
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Không đọc được voices_v3_nano.json"
            case .malformed(let reason): return "voices_v3_nano.json không hợp lệ: \(reason)"
            }
        }
    }

    static func load(modelStore: VieNeuModelStore) throws -> VieNeuVoiceCatalog {
        guard let data = try? Data(contentsOf: modelStore.url(for: "voices_v3_nano.json")) else {
            throw LoadError.unreadable
        }
        let raw = try JSONDecoder().decode(RawCatalog.self, from: data)

        var presets: [Preset] = []
        for (name, entry) in raw.presets {
            let flattened = entry.style.flatMap { $0 }
            guard entry.speaker_emb.count == speakerEmbeddingCount else {
                throw LoadError.malformed("\(name): speaker_emb có \(entry.speaker_emb.count) phần tử, cần \(speakerEmbeddingCount)")
            }
            guard flattened.count == styleCount else {
                throw LoadError.malformed("\(name): style có \(flattened.count) phần tử, cần \(styleCount)")
            }
            presets.append(Preset(
                voice: Voice(name: name),
                gender: entry.gender,
                summary: entry.description,
                speakerEmbedding: entry.speaker_emb,
                style: flattened
            ))
        }
        guard !presets.isEmpty else { throw LoadError.malformed("không có giọng nào") }

        presets.sort { lhs, rhs in
            if lhs.voice.name == raw.default_voice { return true }
            if rhs.voice.name == raw.default_voice { return false }
            return lhs.voice.name.localizedStandardCompare(rhs.voice.name) == .orderedAscending
        }

        return VieNeuVoiceCatalog(presets: presets, defaultVoiceName: raw.default_voice)
    }

    private struct RawCatalog: Decodable {
        let default_voice: String
        let presets: [String: RawPreset]

        struct RawPreset: Decodable {
            let description: String
            let gender: String
            let speaker_emb: [Float]
            let style: [[Float]]
        }
    }
}
