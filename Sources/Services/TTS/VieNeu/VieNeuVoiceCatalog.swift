import Foundation

/// Danh sách giọng của **VieNeu-TTS v3 Nano**: 11 giọng preset đọc từ `voices_v3_nano.json` **cộng**
/// các giọng do người dùng tạo (nhân bản) đọc từ `VieNeuCustomVoiceStore`.
///
/// Mỗi giọng chỉ là **hai mảng số** — không có file model riêng: `speaker_emb` (192-d x-vector) và
/// `style` (50 × 256 style token). Vì vậy "tải model" của engine này là tải **một** bộ graph dùng chung
/// cho cả 11 giọng, khác hẳn Piper (mỗi giọng một file `.onnx`).
///
/// **Gộp ở đây, không ở engine.** `VieNeuTTSEngine.prepareLocked()` chỉ gọi
/// `VieNeuVoiceCatalog.load(modelStore:)` rồi tra `preset(named:)`, còn `VieNeuTTSService.availableVoices()`
/// cũng chỉ gọi `load(...).presets.map(\.voice)`. Nên chỉ cần `load` trả về danh sách đã gộp là **cả hai
/// đường** thấy giọng user mà **không phải sửa một dòng nào** ở engine — đúng plan C2
/// (`VieNeuTTSEngine.swift` đúng 400 dòng, hết chỗ).
///
/// **Thứ tự hiển thị**: giọng user (theo tên) → giọng mặc định → còn lại (theo alphabet). `presets` là
/// một object JSON; `JSONDecoder` trả về `Dictionary` nên thứ tự khoá mất, vì vậy phần preset phải tự
/// xếp thay vì để thứ tự ngẫu nhiên theo hash.
struct VieNeuVoiceCatalog: Sendable {
    struct Preset: Sendable {
        let voice: Voice
        let gender: String
        let summary: String
        /// 192 phần tử.
        let speakerEmbedding: [Float]
        /// 50 × 256 = 12.800 phần tử, đã làm phẳng theo hàng.
        let style: [Float]

        /// `true` khi đây là giọng do người dùng **nhân bản**. Nhận diện qua `gender` — cùng hằng số mà
        /// UI và catalog dùng (`customGender`) để hai bên không thể lệch nhau. Dùng để ép chế độ
        /// chất lượng `.high` (xem `VieNeuSynthesisPolicy.effectiveMode`).
        var isCloned: Bool { gender == VieNeuVoiceCatalog.customGender }
    }

    let presets: [Preset]
    let defaultVoiceName: String

    /// Kích thước đã xác minh từ `voices_v3_nano.json` thật (2,3 MB, 11 giọng).
    static let speakerEmbeddingCount = 192
    static let styleRows = 50
    static let styleColumns = 256
    static var styleCount: Int { styleRows * styleColumns }

    /// Nhãn cho giọng do người dùng tạo. Hằng số để UI và catalog không lệch nhau khi so `gender`.
    static let customGender = "custom"
    static let customSummary = "Giọng nhân bản"

    var defaultPreset: Preset? {
        presets.first { $0.voice.name == defaultVoiceName }
            ?? presets.first { $0.gender != Self.customGender }
            ?? presets.first
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

    /// `customStore` mặc định `nil` ⇒ tự dựng từ `modelStore.rootURL`. Truyền vào khi bên gọi đã có sẵn
    /// thực thể (UI) để không phải dựng lại thư mục.
    static func load(
        modelStore: VieNeuModelStore,
        customStore: VieNeuCustomVoiceStore? = nil
    ) throws -> VieNeuVoiceCatalog {
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

        // Giọng user xếp **lên đầu** (quyết định đã chốt #2): họ vừa tạo nó nên đó là thứ họ muốn thấy
        // trước. `VieNeuCustomVoiceStore.init` **không** chạm đĩa nên gọi ở đây (đường đọc, và cả
        // `prepareLocked` qua đó) là an toàn.
        let store = customStore ?? VieNeuCustomVoiceStore(rootURL: modelStore.rootURL)
        return VieNeuVoiceCatalog(
            presets: customPresets(from: store) + presets,
            defaultVoiceName: raw.default_voice
        )
    }

    /// Đổi `Record` của kho giọng user thành `Preset` để dùng **chung một đường** với 11 giọng preset —
    /// nhờ vậy `VieNeuTTSEngine.runChunk` không cần biết giọng đến từ đâu.
    ///
    /// Bản ghi **hỏng** (sai số phần tử) bị **bỏ qua** chứ không ném lỗi: một giọng user lỗi không được
    /// phép làm cả danh sách giọng — kể cả 11 giọng preset — không dùng được.
    private static func customPresets(from store: VieNeuCustomVoiceStore) -> [Preset] {
        store.loadLeniently()
            .filter { $0.speakerEmbedding.count == speakerEmbeddingCount && $0.style.count == styleCount }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { record in
                Preset(
                    voice: Voice(id: "custom-\(record.id)", name: record.name),
                    gender: customGender,
                    summary: customSummary,
                    speakerEmbedding: record.speakerEmbedding,
                    style: record.style
                )
            }
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
