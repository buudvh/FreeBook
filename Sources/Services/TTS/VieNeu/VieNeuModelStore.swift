import Foundation

/// Kho file của engine **VieNeu-TTS v3 Nano**.
///
/// Cố ý **tách khỏi `ModelStore` của Piper** dù cùng nằm dưới `Application Support/FreeBook/TTS`:
/// `ModelStore` được thiết kế quanh cặp `<voiceId>.onnx` + `<voiceId>.onnx.json` và `getLocalVoiceIDs()`
/// của nó quét **mọi** file `.onnx` trong thư mục để suy ra danh sách giọng. Graph của Nano
/// (`text_encoder.onnx`, `duration_predictor.onnx`, `vector_estimator.onnx`, `codec_decoder.onnx`)
/// nằm cùng thư mục đó sẽ bị nó nhận nhầm thành bốn "giọng Piper" và hiện lên màn quản lý model.
///
/// Bố cục:
/// - `.../FreeBook/TTS/VieNeu/Models/` — 6 file lõi tải từ HuggingFace (4 graph + `config.json` +
///   `constants.npz`).
/// - `.../FreeBook/TTS/VieNeu/Assets/` — 2 file tải từ GitHub: `voices_v3_nano.json` (11 giọng preset)
///   và `sea_g2p.bin` (bộ phonemizer).
final class VieNeuModelStore {
    /// Bốn graph ONNX của pipeline Nano, theo đúng thứ tự thi hành.
    static let graphNames = [
        "text_encoder.onnx",
        "duration_predictor.onnx",
        "vector_estimator.onnx",
        "codec_decoder.onnx"
    ]

    /// Hai file cấu hình/trọng số phụ của pipeline (không phải graph).
    static let configNames = ["config.json", "constants.npz"]

    /// Hai asset tải từ nguồn khác HuggingFace.
    static let assetNames = ["voices_v3_nano.json", "sea_g2p.bin"]

    /// Toàn bộ file bắt buộc phải có trước khi engine chạy được.
    static var requiredNames: [String] { graphNames + configNames + assetNames }

    let rootURL: URL
    let modelsURL: URL
    let assetsURL: URL

    init(fileManager: FileManager = .default) throws {
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        self.rootURL = appSupport.appendingPathComponent("FreeBook/TTS/VieNeu", isDirectory: true)
        self.modelsURL = rootURL.appendingPathComponent("Models", isDirectory: true)
        self.assetsURL = rootURL.appendingPathComponent("Assets", isDirectory: true)
        try fileManager.createDirectory(at: modelsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
    }

    // MARK: - Đường dẫn

    func url(for name: String) -> URL {
        Self.assetNames.contains(name) ? assetsURL.appendingPathComponent(name)
                                       : modelsURL.appendingPathComponent(name)
    }

    func exists(_ name: String) -> Bool {
        FileManager.default.fileExists(atPath: url(for: name).path)
    }

    /// `true` khi đủ **cả 10** file. Không có trạng thái "thiếu một nửa chạy được": pipeline Nano cần
    /// đủ 4 graph, và thiếu `sea_g2p.bin` thì không có phoneme để đưa vào `text_encoder`.
    var isReady: Bool {
        Self.requiredNames.allSatisfy { exists($0) }
    }

    var missingNames: [String] {
        Self.requiredNames.filter { !exists($0) }
    }

    /// Dung lượng đã chiếm — dùng cho nhãn ở màn quản lý model.
    var totalBytes: Int64 {
        Self.requiredNames.reduce(Int64(0)) { partial, name in
            let size = ((try? url(for: name).resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
            return partial + Int64(size)
        }
    }

    // MARK: - Xoá

    /// Xoá **từng file đã biết**, không xoá cả thư mục: `modelsURL`/`assetsURL` còn có thể chứa file
    /// tạm của lượt tải đang dở, và xoá cả cây là cách chắc chắn nhất để một lượt tải song song hỏng.
    func deleteAll() throws {
        let fileManager = FileManager.default
        for name in Self.requiredNames where exists(name) {
            try fileManager.removeItem(at: url(for: name))
        }
    }
}
