import Foundation

/// Đọc `voices_v3_turbo.json` thành danh sách giọng dùng được.
///
/// **Phải là bản chính thức của SDK VieNeu** (20 giọng, mỗi giọng có `speaker_emb` 192 số và
/// `codes` 50×16). Bản cũ hơn từng dùng khoá `reserved_id` và không có `speaker_emb`; bộ
/// `onnx_int8` khai `use_speaker_embedding = true` nên thiếu `speaker_emb` là giọng sẽ trôi hoàn
/// toàn khỏi giọng mẫu.
struct VieNeuVoiceCatalog: Sendable {
    let voices: [VieNeuVoice]
    let defaultVoiceName: String

    private struct RawFile: Decodable {
        let default_voice: String?
        let presets: [String: RawPreset]
    }

    private struct RawPreset: Decodable {
        let description: String?
        let gender: String?
        let region: String?
        let style: String?
        let speaker_emb: [Float]?
        let codes: [[Int32]]
    }

    static let expectedSpeakerEmbeddingDimension = 192
    static let expectedCodebookCount = 16

    init(jsonURL: URL) throws {
        let data = try Data(contentsOf: jsonURL)
        let raw = try JSONDecoder().decode(RawFile.self, from: data)

        var parsed: [VieNeuVoice] = []
        var rejected: [String] = []

        for (name, preset) in raw.presets {
            guard let embedding = preset.speaker_emb,
                  embedding.count == Self.expectedSpeakerEmbeddingDimension else {
                rejected.append(name)
                continue
            }
            guard !preset.codes.isEmpty,
                  preset.codes.allSatisfy({ $0.count == Self.expectedCodebookCount }) else {
                rejected.append(name)
                continue
            }
            parsed.append(VieNeuVoice(
                name: name,
                description: preset.description ?? "",
                gender: preset.gender ?? "",
                region: preset.region ?? "",
                style: preset.style ?? "",
                speakerEmbedding: embedding,
                referenceCodes: preset.codes
            ))
        }

        guard !parsed.isEmpty else {
            let detail = rejected.isEmpty ? "file không có preset nào" : "mọi preset đều thiếu speaker_emb hoặc codes"
            throw TTSError.internalError("voices_v3_turbo.json không dùng được: \(detail)")
        }

        if !rejected.isEmpty {
            AppLogger.shared.log(
                "🗣️ [VieNeuVoiceCatalog] Bỏ \(rejected.count) preset thiếu speaker_emb/codes: \(rejected.joined(separator: ", "))"
            )
        }

        // Sắp theo tên để Picker không nhảy thứ tự mỗi lần dựng lại (JSON dictionary không có thứ tự).
        self.voices = parsed.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let preferred = raw.default_voice ?? ""
        self.defaultVoiceName = self.voices.contains(where: { $0.name == preferred })
            ? preferred
            : (self.voices.first?.name ?? "")
    }

    func voice(named name: String) -> VieNeuVoice? {
        voices.first { $0.name == name }
    }

    /// Giọng để dùng khi tên yêu cầu không có (người dùng đổi file model, hoặc còn lưu tên cũ).
    func resolve(_ requestedName: String) -> VieNeuVoice? {
        voice(named: requestedName) ?? voice(named: defaultVoiceName) ?? voices.first
    }
}
