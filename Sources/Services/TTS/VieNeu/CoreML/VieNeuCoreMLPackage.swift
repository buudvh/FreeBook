import Foundation

/// Gói graph **Core ML đọc truyện thật** của Nano cho vòng thử P1b (`Scripts/vieneu_nano_coreml_export.py`): thư mục
/// `nano-coreml/` của kho HF `raikiri1498/VieNeu-TTS`, kiểm dung lượng + sha256 theo `manifest.json`.
///
/// Định dạng 3 (1.3.915): Gemm lưu trọng số chuyển vị (`transB=1`) để Core ML EP cất trọng số vào `weight.bin` thay vì
/// viết thành chữ trong `model.mil` (báo cáo §13–14). File trọng số chuyển vị **cùng số byte** với bản cũ ⇒ `download`
/// so sha256, không chỉ so dung lượng.
///
/// Trên máy (`FreeBook/TTS/VieNeu/CoreML/`, thuộc loại "TTS" của màn Dung lượng):
/// - `Package/` — graph VE / codec từng bucket + hai file trọng số dùng chung + golden;
/// - `Cache/` — bản Core ML đã biên dịch (`ModelCacheDirectory` của ORT, khoảng 150 MB mỗi bucket VE, 100 MB mỗi bucket
///   codec). Tải lại gói hay xoá gói đều **xoá cache** (bản biên dịch cũ không còn khớp graph);
/// - `Cache-noopt/` — bản thử P2b-0 của 1.3.913 (tắt tối ưu ORT, vô ích — §14); chỉ còn để dọn khi tải gói / xoá;
/// - `Results/` — báo cáo của lượt đo tự động.
final class VieNeuCoreMLPackage: Sendable {
    /// Đọc theo nhánh `main` như `VieNeuNanoStaticPackage` — an toàn vì mọi file kiểm sha256 theo manifest cùng lượt.
    static let remoteBaseURL = "https://huggingface.co/\(VieNeuModelMirror.repository)/resolve/main/nano-coreml/"
    static let manifestName = "manifest.json"
    static let supportedFormat = 3

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
    /// Bản thử P2b-0 (1.3.913) — không còn dùng, chỉ đếm dung lượng + dọn.
    let legacyNoOptCacheDirectory: URL
    let resultsURL: URL

    init() throws {
        rootURL = try VieNeuModelStore().rootURL.appendingPathComponent("CoreML", isDirectory: true)
        directory = rootURL.appendingPathComponent("Package", isDirectory: true)
        cacheDirectory = rootURL.appendingPathComponent("Cache", isDirectory: true)
        legacyNoOptCacheDirectory = rootURL.appendingPathComponent("Cache-noopt", isDirectory: true)
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
    /// Gồm cả bản thử P2b-0 cũ (`Cache-noopt/`) — màn thử hiện một con số cho nút Xoá.
    var cacheBytes: Int64 { Self.bytes(in: cacheDirectory) + Self.bytes(in: legacyNoOptCacheDirectory) }

    /// Kết quả một lần `download`: bao nhiêu file phải tải, có xoá cache biên dịch không.
    struct DownloadResult: Sendable {
        var downloadedFiles = 0
        var downloadedBytes: Int64 = 0
        var clearedCache = false
    }

    /// Tải manifest rồi mọi file thiếu / khác; có file mới ⇒ xoá cache biên dịch.
    ///
    /// Một file được giữ khi **đúng dung lượng và đúng sha256** — sha lấy từ manifest đang có trên máy, khác (hoặc chưa
    /// có) thì băm file (1.3.915: file trọng số định dạng 3 cùng số byte với bản 2, so dung lượng thì giữ trọng số cũ
    /// đi với graph mới ⇒ ra sai mà không báo lỗi). Manifest mới chỉ ghi đè bản cũ **sau** khi đủ file, để lượt bị ngắt
    /// vẫn còn đối chiếu được.
    @discardableResult
    func download(progress: @escaping @Sendable (String, Int64, Int64) -> Void) async throws -> DownloadResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard let manifestURL = URL(string: Self.remoteBaseURL + Self.manifestName) else {
            throw PackageError.badURL(Self.manifestName)
        }
        let pendingManifest = url(Self.manifestName + ".new")
        try await VieNeuTurboModelClient.transfer(
            session: .shared, from: manifestURL, to: pendingManifest, name: Self.manifestName,
            expectedBytes: nil, progress: nil
        )
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: pendingManifest))
        guard manifest.format == Self.supportedFormat else {
            try? FileManager.default.removeItem(at: pendingManifest)
            throw PackageError.unsupportedFormat(manifest.format)
        }
        let previousSha = Self.fileHashes(at: url(Self.manifestName))

        let total = manifest.totalBytes
        var done: Int64 = 0
        var result = DownloadResult()
        for file in manifest.files {
            try Task.checkCancellation()
            let destination = url(file.name)
            if VieNeuTurboModelStore.fileSize(at: destination) == file.bytes,
               previousSha[file.name] == file.sha256 || (try? VieNeuNanoStaticPackage.sha256(of: destination)) == file.sha256 {
                done += file.bytes
                progress(file.name, done, total)
                continue
            }
            try? FileManager.default.removeItem(at: destination)
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
            result.downloadedFiles += 1
            result.downloadedBytes += file.bytes
            done += file.bytes
            progress(file.name, done, total)
        }
        try? FileManager.default.removeItem(at: url(Self.manifestName))
        try FileManager.default.moveItem(at: pendingManifest, to: url(Self.manifestName))
        if result.downloadedFiles > 0 {
            deleteCache()
            result.clearedCache = true
        }
        AppLogger.shared.log("🎙️ [VieNeuCoreML] Gói Core ML sẵn sàng: \(manifest.files.count) file, \(total) byte, "
            + "tải \(result.downloadedFiles) file")
        return result
    }

    /// sha256 theo tên file của một manifest bất kỳ định dạng (chỉ đọc `files`); không đọc được ⇒ rỗng.
    private static func fileHashes(at manifestURL: URL) -> [String: String] {
        struct Files: Decodable {
            let files: [Manifest.File]
        }
        guard let data = try? Data(contentsOf: manifestURL),
              let decoded = try? JSONDecoder().decode(Files.self, from: data) else { return [:] }
        return Dictionary(decoded.files.map { ($0.name, $0.sha256) }, uniquingKeysWith: { first, _ in first })
    }

    func deleteCache() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        try? FileManager.default.removeItem(at: legacyNoOptCacheDirectory)
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
