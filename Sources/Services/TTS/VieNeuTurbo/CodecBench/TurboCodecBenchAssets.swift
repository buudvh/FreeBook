import Foundation

/// **TẠM — màn đo "Codec Turbo: AMX vs Neural Engine"** (1.3.932): tải graph codec MOSS chính thức (HF
/// OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX, revision ghim) vào `Caches/turbo-codec-bench/` (~45 MB, hệ điều hành được
/// xoá; xoá màn đo thì xoá luôn thư mục này). Xoá cùng màn đo khi có kết luận.
enum TurboCodecBenchAssets {
    static let revision = "ceff0d0749bfb3fa2d61149794ec6feef0d1e1ae"
    static let modelFileName = "moss_audio_tokenizer_decode_full.onnx"
    /// Đúng chuỗi `location` của external data ghi trong graph (nạp vào bộ nhớ theo tên này).
    static let weightFileName = "moss_audio_tokenizer_decode_shared.data"
    /// Cỡ byte đúng của từng file (đọc từ API của HF ngày 2026-11-14) — lệch ⇒ tải lại.
    static let byteCounts: [String: Int64] = [
        modelFileName: 681_902,
        weightFileName: 44_198_912
    ]

    static var directory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("turbo-codec-bench", isDirectory: true)
    }

    static var modelURL: URL { directory.appendingPathComponent(modelFileName) }
    static var weightURL: URL { directory.appendingPathComponent(weightFileName) }
    static var coreMLCacheDirectory: URL { directory.appendingPathComponent("coreml-cache", isDirectory: true) }

    /// Tải những file còn thiếu / sai cỡ. `progress` nhận câu hiển thị.
    static func ensureDownloaded(progress: @escaping @Sendable (String) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: coreMLCacheDirectory, withIntermediateDirectories: true)
        for (name, expected) in byteCounts.sorted(by: { $0.value < $1.value }) {
            let target = directory.appendingPathComponent(name)
            if fileSize(target) == expected { continue }
            progress("Đang tải \(name) (\(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file)))…")
            let source = URL(string: "https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/resolve/\(revision)/\(name)")!
            let (downloaded, response) = try await URLSession.shared.download(from: source)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw TurboCodecProbeSession.ProbeError(message: "Tải \(name) lỗi HTTP \(http.statusCode)")
            }
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: downloaded, to: target)
            guard fileSize(target) == expected else {
                try? FileManager.default.removeItem(at: target)
                throw TurboCodecProbeSession.ProbeError(message: "\(name) tải về sai cỡ")
            }
        }
    }

    private static func fileSize(_ url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }
}
