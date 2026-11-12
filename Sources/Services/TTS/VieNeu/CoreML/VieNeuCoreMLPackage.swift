import Foundation

/// Gói graph **Core ML đọc truyện thật** của Nano cho vòng thử P1b (`Scripts/vieneu_nano_coreml_export.py`): thư mục
/// `nano-coreml/` của kho HF `raikiri1498/VieNeu-TTS`, kiểm dung lượng + sha256 theo `manifest.json`.
///
/// Trên máy (`FreeBook/TTS/VieNeu/CoreML/`, thuộc loại "TTS" của màn Dung lượng):
/// - `Package/` — graph VE / codec từng bucket + hai file trọng số dùng chung + golden;
/// - `Cache/` — bản Core ML đã biên dịch (`ModelCacheDirectory` của ORT, khoảng 150 MB mỗi bucket VE, 100 MB mỗi bucket
///   codec). Tải lại gói hay xoá gói đều **xoá cache** (bản biên dịch cũ không còn khớp graph);
/// - `Results/` — báo cáo của lượt đo tự động.
final class VieNeuCoreMLPackage: Sendable {
    /// Đọc theo nhánh `main` như `VieNeuNanoStaticPackage` — an toàn vì mọi file kiểm sha256 theo manifest cùng lượt.
    static let remoteBaseURL = "https://huggingface.co/\(VieNeuModelMirror.repository)/resolve/main/nano-coreml/"
    static let manifestName = "manifest.json"
    static let supportedFormat = 2

    struct Manifest: Decodable, Sendable {
        struct File: Decodable, Sendable {
            let name: String
            let bytes: Int64
            let sha256: String
        }

        let format: Int
        let lengthFrozen: Int
        let veBuckets: [Int]
        let codecBuckets: [Int]
        let veWeights: String
        let codecWeights: String
        let goldenChunks: Int
        let files: [File]

        var totalBytes: Int64 { files.reduce(0) { $0 + $1.bytes } }
    }

    enum PackageError: LocalizedError {
        case unsupportedFormat(Int)
        case badURL(String)
        case checksum(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let value):
                return "manifest Core ML định dạng \(value) — app này chỉ hiểu \(VieNeuCoreMLPackage.supportedFormat)"
            case .badURL(let name): return "URL không hợp lệ cho \(name)"
            case .checksum(let name): return "\(name) sai sha256 — tải lại"
            }
        }
    }

    let rootURL: URL
    let directory: URL
    let cacheDirectory: URL
    let resultsURL: URL

    init() throws {
        rootURL = try VieNeuModelStore().rootURL.appendingPathComponent("CoreML", isDirectory: true)
        directory = rootURL.appendingPathComponent("Package", isDirectory: true)
        cacheDirectory = rootURL.appendingPathComponent("Cache", isDirectory: true)
        resultsURL = rootURL.appendingPathComponent("Results", isDirectory: true)
    }

    func url(_ name: String) -> URL {
        directory.appendingPathComponent(name, isDirectory: false)
    }

    var manifest: Manifest? {
        guard let data = try? Data(contentsOf: url(Self.manifestName)),
              let decoded = try? JSONDecoder().decode(Manifest.self, from: data),
              decoded.format == Self.supportedFormat else { return nil }
        return decoded
    }

    var isComplete: Bool {
        guard let manifest else { return false }
        return manifest.files.allSatisfy { VieNeuTurboModelStore.fileSize(at: url($0.name)) == $0.bytes }
    }

    var packageBytes: Int64 { Self.bytes(in: directory) }
    var cacheBytes: Int64 { Self.bytes(in: cacheDirectory) }

    /// Tải manifest rồi mọi file còn thiếu / sai dung lượng; có file mới ⇒ xoá cache biên dịch.
    func download(progress: @escaping @Sendable (String, Int64, Int64) -> Void) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let manifestURL = URL(string: Self.remoteBaseURL + Self.manifestName) else {
            throw PackageError.badURL(Self.manifestName)
        }
        try await VieNeuTurboModelClient.transfer(
            session: .shared, from: manifestURL, to: url(Self.manifestName), name: Self.manifestName,
            expectedBytes: nil, progress: nil
        )
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url(Self.manifestName)))
        guard manifest.format == Self.supportedFormat else { throw PackageError.unsupportedFormat(manifest.format) }

        let total = manifest.totalBytes
        var done: Int64 = 0
        var downloadedAny = false
        for file in manifest.files {
            let destination = url(file.name)
            if VieNeuTurboModelStore.fileSize(at: destination) == file.bytes {
                done += file.bytes
                progress(file.name, done, total)
                continue
            }
            guard let source = URL(string: Self.remoteBaseURL + file.name) else { throw PackageError.badURL(file.name) }
            let base = done
            try await VieNeuTurboModelClient.transfer(
                session: .shared, from: source, to: destination, name: file.name, expectedBytes: file.bytes,
                progress: { completed, _ in progress(file.name, base + completed, total) }
            )
            guard try VieNeuNanoStaticPackage.sha256(of: destination) == file.sha256 else {
                try? FileManager.default.removeItem(at: destination)
                throw PackageError.checksum(file.name)
            }
            downloadedAny = true
            done += file.bytes
            progress(file.name, done, total)
        }
        if downloadedAny { deleteCache() }
        AppLogger.shared.log("🎙️ [VieNeuCoreML] Gói Core ML sẵn sàng: \(manifest.files.count) file, \(total) byte")
    }

    func deleteCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
    }

    /// Kết quả dọn cache: số mục giữ / xoá + một đường dẫn bản biên dịch tìm thấy (tương đối với `Cache/`) để nhật ký
    /// chứng minh bản lưu được nhận.
    struct CacheCleanup: Sendable {
        var kept = 0
        var removed = 0
        var sampleCompiledPath: String?

        var summary: String {
            "giữ \(kept) bản biên dịch, dọn \(removed) bản dở" + (sampleCompiledPath.map { " (vd \($0))" } ?? "")
        }
    }

    /// Xoá bản biên dịch **dở** (1.3.906): ORT coi graph là "đã có bản lưu" chỉ cần thư mục gói MLProgram tồn tại
    /// (`ModelBuilder`: `FolderExists(model_output_path_)`), mà thư mục đó được ghi **trước** khi biên dịch — app bị giết
    /// giữa chừng thì lượt sau dùng lại gói dở. Mục xong có `compiled_model.mlmodelc`; thiếu ⇒ xoá cả mục.
    ///
    /// Bản 1.3.906–910 tìm `compiled_model.mlmodelc` ngay trong `<id>_static_mlprogram/`, nhưng ORT 1.24.2 đặt gói ở
    /// `<id>_static_mlprogram/model` (`GetModelOutputPath`) và để bản biên dịch **bên trong gói** (`CompileOrReadCachedModel`
    /// của model.mm) ⇒ xoá nhầm mọi mục hợp lệ, lần nào cũng biên dịch lại (đo tự động 2026-11-12: chạy tiếp mất 265 s).
    /// Giờ tìm ở cả tầng 1 lẫn tầng 2 để không phụ thuộc bố cục.
    @discardableResult
    func cleanCacheEntries() -> CacheCleanup {
        let fileManager = FileManager.default
        var result = CacheCleanup()
        guard let keys = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) else {
            return result
        }
        for key in keys {
            guard let entries = try? fileManager.contentsOfDirectory(at: key, includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.lastPathComponent.hasSuffix("_mlprogram") {
                if let compiled = Self.compiledModelPath(in: entry) {
                    result.kept += 1
                    if result.sampleCompiledPath == nil {
                        result.sampleCompiledPath = "\(key.lastPathComponent)/\(entry.lastPathComponent)/\(compiled)"
                    }
                } else {
                    try? fileManager.removeItem(at: entry)
                    result.removed += 1
                }
            }
        }
        return result
    }

    /// Đường dẫn (tương đối với `entry`) của `compiled_model.mlmodelc` ở tầng 1 hoặc tầng 2; `nil` = chưa biên dịch xong.
    private static func compiledModelPath(in entry: URL) -> String? {
        let fileManager = FileManager.default
        let name = "compiled_model.mlmodelc"
        if fileManager.fileExists(atPath: entry.appendingPathComponent(name, isDirectory: true).path) {
            return name
        }
        let children = (try? fileManager.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil)) ?? []
        for child in children
        where fileManager.fileExists(atPath: child.appendingPathComponent(name, isDirectory: true).path) {
            return "\(child.lastPathComponent)/\(name)"
        }
        return nil
    }

    /// Xoá gói + cache + kết quả.
    func deleteAll() throws {
        if FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
    }

    private static func bytes(in directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            total += VieNeuTurboModelStore.fileSize(at: file)
        }
        return total
    }
}
