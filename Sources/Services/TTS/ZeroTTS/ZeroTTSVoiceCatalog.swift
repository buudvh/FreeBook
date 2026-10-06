import Foundation

/// Danh mục giọng **preset** của ZeroTTS và bộ nạp embedding giọng.
///
/// Bản open-source **không** kèm voice encoder — nó chỉ *nạp* giọng, không *tạo* giọng từ audio. Giọng
/// riêng phải lấy từ platform.zeroweight.ai dưới dạng `.zip`. Vì vậy spike chỉ dùng tám giọng preset có
/// sẵn trên kho weights.
struct ZeroTTSVoiceCatalog {
    struct Voice: Identifiable, Hashable {
        let name: String
        let displayName: String
        let summary: String

        var id: String { name }
    }

    enum CatalogError: LocalizedError {
        case malformed(String)
        case badEmbedding(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let detail): return "`voices/index.json` không đúng khuôn: \(detail)"
            case .badEmbedding(let detail): return "Embedding giọng không hợp lệ: \(detail)"
            }
        }
    }

    static func load(from indexURL: URL) throws -> [Voice] {
        let data = try Data(contentsOf: indexURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.malformed("không phải JSON object")
        }
        guard let list = root["voices"] as? [[String: Any]] else {
            throw CatalogError.malformed("thiếu mảng `voices`")
        }
        return list.compactMap { entry in
            guard let name = entry["name"] as? String, !name.isEmpty else { return nil }
            return Voice(name: name,
                         displayName: (entry["display_name"] as? String) ?? name,
                         summary: (entry["description"] as? String) ?? "")
        }
    }

    /// `voice.bin` là **float32 little-endian thô**, shape `(1, V, D)` = `(1, 10, 768)`.
    ///
    /// `expectedCount` khác `0` thì số phần tử phải khớp **đúng**: `cross_kv`/`packed_kv` đều khai chiều
    /// theo `n_voice_queries`, nên một giọng sai kích thước sẽ làm `prefix_step` lệch shape — và ORT báo
    /// lỗi ở tận đó chứ không phải ở chỗ nạp giọng.
    static func loadEmbedding(from url: URL, expectedCount: Int) throws -> [Float] {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count >= 4, data.count % 4 == 0 else {
            throw CatalogError.badEmbedding("\(url.lastPathComponent): \(data.count) byte không chia hết cho 4")
        }
        let count = data.count / 4
        if expectedCount > 0, count != expectedCount {
            throw CatalogError.badEmbedding("\(url.lastPathComponent): có \(count) float, cần \(expectedCount)")
        }
        var values = [Float](repeating: 0, count: count)
        values.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let base = source.baseAddress else { return }
                let byteCount = min(destination.count, source.count)
                destination.copyBytes(from: UnsafeRawBufferPointer(start: base, count: byteCount))
            }
        }
        return values
    }
}
