import Foundation

/// Kho file của ZeroTTS trên máy.
///
/// **Mọi file nằm phẳng trong một thư mục.** Đây không phải cho gọn: graph codec tham chiếu file external
/// data của nó bằng đường dẫn **tương đối cạnh chính nó**, mà `ZeroTTSORTCreate` lại mở cả bốn graph bằng
/// tên trần trong **một** thư mục — nên `moss_audio_tokenizer_decode_shared.data` bắt buộc nằm cạnh
/// `moss_audio_tokenizer_decode_full.onnx`, không được giữ cây `onnx/codec/` như trên kho weights.
final class ZeroTTSModelStore {
    /// Tên thư mục dưới `Application Support`.
    static let directoryName = "ZeroTTS"

    /// Ánh xạ `đường dẫn trên kho weights → tên file cục bộ`.
    static let remoteToLocal: [(remote: String, local: String)] = [
        ("config.json", "config.json"),
        ("tokenizer.json", "tokenizer.json"),
        ("voices/index.json", "voices_index.json"),
        ("onnx/text_encoder.onnx", "text_encoder.onnx"),
        ("onnx/prefix_step.onnx", "prefix_step.onnx"),
        ("onnx/local_frame_decode.onnx", "local_frame_decode.onnx"),
        ("onnx/codec/moss_audio_tokenizer_decode_full.onnx", "moss_audio_tokenizer_decode_full.onnx"),
        ("onnx/codec/moss_audio_tokenizer_decode_shared.data", "moss_audio_tokenizer_decode_shared.data")
    ]

    /// File bắt buộc phải có trước khi engine nạp được.
    static var requiredFileNames: [String] { remoteToLocal.map(\.local) }

    /// `voice.bin` của một giọng, đã làm phẳng thành `voice-<tên>.bin`.
    static func voiceFileName(_ name: String) -> String { "voice-\(name).bin" }

    enum StoreError: LocalizedError {
        case unavailable(String)

        var errorDescription: String? {
            switch self {
            case .unavailable(let detail): return "Không dựng được kho model ZeroTTS: \(detail)"
            }
        }
    }

    let rootURL: URL

    init() throws {
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory,
                                                   in: .userDomainMask,
                                                   appropriateFor: nil,
                                                   create: true)
            let root = base.appendingPathComponent(Self.directoryName, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            self.rootURL = root
        } catch {
            throw StoreError.unavailable(error.localizedDescription)
        }
    }

    func url(for fileName: String) -> URL {
        rootURL.appendingPathComponent(fileName)
    }

    /// Tên các giọng đã có `voice-<tên>.bin` trên máy.
    var voiceNames: [String] {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: rootURL.path)) ?? []
        let prefix = "voice-"
        let suffix = ".bin"
        return contents
            .filter { $0.hasPrefix(prefix) && $0.hasSuffix(suffix) }
            .map { String($0.dropFirst(prefix.count).dropLast(suffix.count)) }
            .sorted()
    }

    /// File còn thiếu. Có ít nhất một giọng là điều kiện **bắt buộc**: model có thể chạy không giọng
    /// (unconditional) nhưng kết quả không ổn định giữa các lượt, nên nó không phải đường của spike.
    var missingNames: [String] {
        let fileManager = FileManager.default
        var missing = Self.requiredFileNames.filter { !fileManager.fileExists(atPath: url(for: $0).path) }
        if voiceNames.isEmpty { missing.append("voice-<tên>.bin") }
        return missing
    }

    var isReady: Bool { missingNames.isEmpty }

    /// Tổng dung lượng đã tải — dùng cho khối "Model" của màn thử.
    var totalBytes: Int {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: rootURL,
                                                                  includingPropertiesForKeys: [.fileSizeKey],
                                                                  options: [.skipsHiddenFiles]) else {
            return 0
        }
        return contents.reduce(0) { partial, fileURL in
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return partial + size
        }
    }

    func deleteAll() throws {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: rootURL,
                                                                  includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles]) else {
            return
        }
        for fileURL in contents {
            try? fileManager.removeItem(at: fileURL)
        }
    }
}
