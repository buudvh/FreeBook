import Foundation

/// `gguf/voices/manifest.json` của VieNeu-TTS v3 Turbo: `{ "default": "<id>", "voices": [{id, name, label, frames}] }`.
///
/// Mỗi giọng là **hai file chữ** (`ref_codes.txt` = mã tham chiếu, `speaker.emb.txt` = 192 số) đưa thẳng cho
/// audio.cpp qua `reference_codes_file` / `speaker_embedding_file` — không có bước mã hoá giọng trên máy.
struct VieNeuTurboVoiceManifest: Decodable, Sendable {
    struct Voice: Decodable, Sendable, Identifiable, Hashable {
        let id: String
        let name: String
        let label: String?
        /// Số khung 80 ms của đoạn tham chiếu — chỉ để hiện, audio.cpp tự đọc từ `ref_codes.txt`.
        let frames: Int?

        var displayName: String { label ?? name }

        /// Giọng tác giả tuyển chọn — `label` mở đầu bằng ⭐ (10/25 giọng ở revision đang ghim).
        var isFeatured: Bool { label?.hasPrefix("⭐") ?? false }

        /// "Nam · Bắc · tự nhiên" rút từ `label` dạng "⭐ Minh Quân Pro — Nam · Bắc · Phong cách tự nhiên": lấy phần sau
        /// gạch dài, bỏ chữ "Phong cách" / "Giọng đọc" ở mục phong cách. `nil` khi `label` không đúng khuôn đó.
        var traitsSummary: String? {
            guard let label, let separator = label.range(of: " — ") else { return nil }
            let parts = label[separator.upperBound...]
                .components(separatedBy: " · ")
                .map { part -> String in
                    var trimmed = part.trimmingCharacters(in: .whitespaces)
                    for prefix in ["Phong cách ", "Giọng đọc "] where trimmed.hasPrefix(prefix) {
                        trimmed = String(trimmed.dropFirst(prefix.count))
                    }
                    return trimmed
                }
                .filter { !$0.isEmpty }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    let defaultVoiceId: String?
    let voices: [Voice]

    private enum CodingKeys: String, CodingKey {
        case defaultVoiceId = "default"
        case voices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        defaultVoiceId = try container.decodeIfPresent(String.self, forKey: .defaultVoiceId)
        // Id đi thẳng vào đường dẫn file ⇒ bỏ mọi giọng có id lạ thay vì tin manifest tải về.
        voices = try container.decode([Voice].self, forKey: .voices)
            .filter { VieNeuTurboModelStore.isSafeVoiceId($0.id) }
    }

    static func load(from url: URL) throws -> VieNeuTurboVoiceManifest {
        try JSONDecoder().decode(VieNeuTurboVoiceManifest.self, from: Data(contentsOf: url))
    }

    /// Giọng mặc định của manifest nếu có trong danh sách, không thì giọng đầu tiên.
    var defaultVoice: Voice? {
        voices.first { $0.id == defaultVoiceId } ?? voices.first
    }
}
