import Foundation
import ZIPFoundation

/// Danh mục giọng Kokoro và bộ nạp voicepack.
///
/// Voicepack là file `.pt` của PyTorch, nhưng **thực chất chỉ là một file zip**: entry `*/data/0` chứa đúng
/// mảng float32 thô của tensor. Vì vậy app đọc được nó bằng `ZIPFoundation` mà **không cần torch**, và
/// **không cần chủ repo chuyển sang định dạng khác**.
///
/// Điều này đã được kiểm trên file thật: `ngoc_huyen/data/0` = 522 240 byte = 130 560 float32
/// = 510 × 1 × 256, khớp `KokoroConfig.maxPhonemes × KokoroConfig.styleWidth`.
struct KokoroVoiceCatalog {
    struct Voice: Identifiable, Hashable {
        let key: String
        let label: String
        let fileName: String

        var id: String { key }
    }

    enum CatalogError: LocalizedError {
        case malformed(String)
        case badVoicepack(String)

        var errorDescription: String? {
            switch self {
            case .malformed(let detail): return "`voices.json` không đúng khuôn: \(detail)"
            case .badVoicepack(let detail): return "Voicepack không đọc được: \(detail)"
            }
        }
    }

    /// `voices.json` có dạng `{ "<key>": { "label": "…", "filename": "voicepacks/<key>.pt" } }`.
    ///
    /// Xếp theo `key` chứ **không** theo `label`: thứ tự phải ổn định giữa các lần mở màn, mà `label` là
    /// tiếng Việt có dấu nên `localizedStandardCompare` phụ thuộc locale.
    static func load(from url: URL) throws -> [Voice] {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatalogError.malformed("không phải JSON object")
        }
        let voices: [Voice] = root.compactMap { key, raw in
            guard let entry = raw as? [String: Any] else { return nil }
            return Voice(key: key,
                         label: (entry["label"] as? String) ?? key,
                         fileName: (entry["filename"] as? String) ?? "voicepacks/\(key).pt")
        }
        guard !voices.isEmpty else { throw CatalogError.malformed("không có giọng nào") }
        return voices.sorted { $0.key < $1.key }
    }

    /// Nạp voicepack thành mảng phẳng `maxPhonemes × styleWidth` float32.
    ///
    /// Kiểm **đúng** kích thước thay vì tin: đọc nhầm một tensor khác trong zip (hoặc zip của bản export
    /// khác) sẽ cho ra `ref_s` sai bề rộng, và triệu chứng là giọng đọc méo chứ **không** phải một lỗi ORT —
    /// đúng loại hỏng im lặng cần chặn ở đây.
    static func loadVoicepack(from url: URL) throws -> [Float] {
        guard let archive = Archive(url: url, accessMode: .read) else {
            throw CatalogError.badVoicepack("\(url.lastPathComponent): không mở được như file zip")
        }
        guard let entry = archive.first(where: { $0.path.hasSuffix("data/0") }) else {
            throw CatalogError.badVoicepack("\(url.lastPathComponent): không có entry kết thúc bằng `data/0`")
        }

        var bytes = Data()
        bytes.reserveCapacity(Int(entry.uncompressedSize))
        _ = try archive.extract(entry) { chunk in bytes.append(chunk) }

        let expectedCount = KokoroConfig.maxPhonemes * KokoroConfig.styleWidth
        let expectedBytes = expectedCount * MemoryLayout<Float>.size
        guard bytes.count == expectedBytes else {
            throw CatalogError.badVoicepack(
                "\(url.lastPathComponent): \(bytes.count) byte, cần \(expectedBytes) "
                + "(\(expectedCount) float32)")
        }

        let byteCount = bytes.count
        var values = [Float](repeating: 0, count: expectedCount)
        values.withUnsafeMutableBytes { destination in
            bytes.withUnsafeBytes { source in
                guard let base = source.baseAddress else { return }
                let copyCount = min(destination.count, byteCount)
                destination.copyBytes(from: UnsafeRawBufferPointer(start: base, count: copyCount))
            }
        }
        return values
    }

    /// Vector style cho một số âm vị cụ thể — `voicepack[min(n, maxPhonemes) - 1]`, đúng
    /// `select_voice_style` của bản tham chiếu.
    static func styleVector(from voicepack: [Float], phonemeCount: Int) throws -> [Float] {
        guard phonemeCount > 0 else {
            throw CatalogError.badVoicepack("số âm vị phải lớn hơn 0")
        }
        let index = min(phonemeCount, KokoroConfig.maxPhonemes) - 1
        let start = index * KokoroConfig.styleWidth
        guard start >= 0, start + KokoroConfig.styleWidth <= voicepack.count else {
            throw CatalogError.badVoicepack("voicepack ngắn hơn chỉ số \(index) cần")
        }
        return Array(voicepack[start..<(start + KokoroConfig.styleWidth)])
    }
}
