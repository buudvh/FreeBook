import Foundation
import CryptoKit

/// Tải 8 file lõi của **VieNeu-TTS v3 Nano** về `VieNeuModelStore` (và, khi được yêu cầu riêng, cả 3
/// graph clone giọng — xem `prefetchCloneGraphs`).
///
/// ## Ghim sha, không lấy `main`
/// Model card của tác giả cảnh báo thẳng là "weights, voices and defaults may change between
/// revisions" — và việc đó **đã xảy ra một lần**: repo `VieNeu-TTS-v3-Nano` từng chứa graph
/// autoregressive (bản dùng trong `VieNeuTTS-Offline`), nay đã đổi sang flow-matching. Vì vậy cả ba
/// nguồn đều ghim sha: model + config + constants theo sha của HuggingFace, hai asset còn lại theo sha
/// commit của GitHub. URL có sha là bất biến, nên app không thể "tự nhiên hỏng" vì upstream sửa file.
///
/// ## Không resume theo byte — cố ý, và đây là điểm lệch plan
/// Plan §4 bước 3 ghi "resume được". Bản này chỉ resume ở **mức từng file**: mỗi file tải vào một file
/// tạm rồi `moveItem` nguyên tử, nên một lượt tải đứt giữa chừng **không** làm hỏng file đã xong và lần
/// chạy sau chỉ tải lại đúng file còn thiếu. Resume theo byte (HTTP `Range` + `URLSession.resumeData`)
/// không làm được với `URLSession.download(from:)` của API async hiện tại, còn `URLSession.bytes(for:)`
/// thì trả từng byte một — 280 MB là không dùng được. Cách làm ở đây **giống hệt** `NghiTTSClient`
/// (`NghiTTSClient.swift:104-155`) nên không tạo ra mô hình tải thứ hai trong app.
///
/// ## Core ML (Phases 3–5)
/// 8 gói Core ML nằm ở repo riêng `raikiri1498/VieNeu-TTS-v3-Nano-CoreML` (publish qua Trusted
/// Publishers OIDC ở Phase 2, commit `68af081`). Mỗi gói là một thư mục `.mlpackage` nhiều file; app
/// tải từng file theo danh sách trong `manifest.json` (có `sha256` + `bytes` từng file) rồi biên dịch
/// `.mlpackage` → `.mlmodelc` (xem `VieNeuCoreMLCompiler`). Việc kiểm SHA lấy thẳng từ `manifest.json`
/// nên **không** cần hardcode — nếu upstream đổi gói, manifest mới sẽ mang SHA mới.
final class VieNeuModelClient {
    /// Sha của `pnnbao-ump/VieNeu-TTS-v3-Nano` tại thời điểm 2026-09-05.
    static let modelRevision = "aba295eb96a6fa6003ebe417cc1f2802a7adc1dc"
    /// Sha của `pnnbao97/VieNeu-TTS` (chứa `src/vieneu/assets/voices_v3_nano.json`).
    static let voicesRevision = "2e982ff857bbe23fffa0c314e0f60da2497e2f4b"
    /// Sha của `pnnbao97/sea-g2p` (chứa `python/sea_g2p/sea_g2p.bin`, 62.829.820 byte).
    static let g2pRevision = "e825173f235d08ea19315b2b279fb11153b44cea"

    /// Sha của repo Core ML (`raikiri1498/VieNeu-TTS-v3-Nano-CoreML`) tại thời điểm publish sạch
    /// (Phase 2, commit `68af081`, run `37019841164`). Repo chỉ chứa 8 `.mlpackage` + `manifest.json`
    /// + 3 `golden/*.npz`, tổng 397,8 MB.
    static let coreMLRevision = "68af081"

    /// Gốc của repo model — **đã ghim sha**. Cả 4 graph chính lẫn 3 graph clone đều nằm ở đây, nên khai
    /// một chỗ và dùng cho cả `sources()` lẫn `cloneSources()`.
    private static var modelBase: String {
        "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Nano/resolve/\(modelRevision)"
    }

    /// Gốc của repo Core ML — **đã ghim sha** (commit `68af081`).
    private static var coreMLBase: String {
        "https://huggingface.co/raikiri1498/VieNeu-TTS-v3-Nano-CoreML/resolve/\(coreMLRevision)"
    }

    private static var voicesURL: String {
        "https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/\(voicesRevision)/src/vieneu/assets/voices_v3_nano.json"
    }

    private static var g2pURL: String {
        "https://raw.githubusercontent.com/pnnbao97/sea-g2p/\(g2pRevision)/python/sea_g2p/sea_g2p.bin"
    }

    struct Source: Sendable {
        let name: String
        let url: URL
        /// Đích ghi trên đĩa. Khác `store.url(for:)` vì Core ML tải vào `CoreML/<name>.mlpackage/…`,
        /// không vào `Models/`/`Assets/`.
        let localURL: URL
        /// SHA-256 mong đợi (từ `manifest.json` của Core ML). `nil` = không kiểm (nguồn ONNX cũ).
        let expectedSha: String?
        /// Kích thước mong đợi (byte). `0` = không kiểm.
        let expectedBytes: Int64
    }

    enum DownloadError: LocalizedError {
        case badURL(String)
        case httpStatus(String, Int)
        case emptyBody(String)
        case shaMismatch(String, String, String)
        case manifestUnavailable

        var errorDescription: String? {
            switch self {
            case .badURL(let name): return "URL không hợp lệ cho \(name)"
            case .httpStatus(let name, let code): return "Tải \(name) thất bại: HTTP \(code)"
            case .emptyBody(let name): return "Tải \(name) thất bại: nội dung rỗng"
            case .shaMismatch(let name, let got, let want): return "Tải \(name) sai SHA (got \(got.prefix(8))… want \(want.prefix(8))…)"
            case .manifestUnavailable: return "Không tải được manifest.json của Core ML"
            }
        }
    }

    private let store: VieNeuModelStore
    private let session: URLSession

    init(store: VieNeuModelStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    /// Tám nguồn, theo thứ tự tải: graph trước (nặng nhất), rồi cấu hình, rồi asset.
    func sources() throws -> [Source] {
        var list: [Source] = []
        for name in VieNeuModelStore.graphNames + VieNeuModelStore.configNames {
            list.append(try source(name: name, urlString: "\(Self.modelBase)/\(name)"))
        }
        list.append(try source(name: "voices_v3_nano.json", urlString: voicesURL))
        list.append(try source(name: "sea_g2p.bin", urlString: g2pURL))
        return list
    }

    /// Ba nguồn của **gói graph clone** (~91 MB), cùng repo và cùng sha với 4 graph chính.
    ///
    /// Tải **riêng** khỏi `sources()`: gói này là tuỳ chọn (chỉ cần khi tạo giọng mới) nên không được
    /// nằm trong `VieNeuModelStore.requiredNames` — xem doc của `cloneGraphNames`.
    func cloneSources() throws -> [Source] {
        try VieNeuModelStore.cloneGraphNames.map { try source(name: $0, urlString: "\(Self.modelBase)/\($0)") }
    }

    private func source(name: String, urlString: String) throws -> Source {
        guard let url = URL(string: urlString) else { throw DownloadError.badURL(name) }
        return Source(name: name, url: url, localURL: store.url(for: name), expectedSha: nil, expectedBytes: 0)
    }

    /// Tải mọi file còn thiếu. Trả về số file **thực sự tải** trong lượt này.
    ///
    /// `progressHandler` nhận `(tên file, tiến độ 0…1)` — tiến độ ở **mức file**, không theo byte, đúng
    /// khuôn `NghiTTSClient.prefetchModels`.
    @discardableResult
    func prefetch(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        try await downloadAll(try sources(), progressHandler: progressHandler)
    }

    /// Tải **gói graph clone** (3 file, ~91 MB). Cùng khuôn tiến độ với `prefetch`.
    @discardableResult
    func prefetchCloneGraphs(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        try await downloadAll(try cloneSources(), progressHandler: progressHandler)
    }

    /// Tải 8 gói Core ML theo `manifest.json` (có SHA + bytes từng file), rồi UI tự biên dịch sau.
    /// Cùng lượt này tải luôn 3 `golden/T{n}.npz` (đầu vào/tham chiếu tự test theo bucket).
    @discardableResult
    func prefetchCoreML(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        let manifest = try await downloadCoreMLManifest()
        var sources = coreMLSources(manifest: manifest)
        sources.append(contentsOf: coreMLGoldenSources(manifest: manifest))
        return try await downloadAll(sources, progressHandler: progressHandler)
    }

    /// Tải và giải mã `manifest.json` của repo Core ML; lưu bản sao tại máy (`store.coreMLManifestURL`).
    func downloadCoreMLManifest() async throws -> CoreMLManifest {
        guard let url = URL(string: "\(Self.coreMLBase)/manifest.json") else { throw DownloadError.badURL("manifest.json") }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.httpStatus("manifest.json", http.statusCode)
        }
        guard !data.isEmpty else { throw DownloadError.manifestUnavailable }
        let manifest = try JSONDecoder().decode(CoreMLManifest.self, from: data)
        try? data.write(to: store.coreMLManifestURL, options: .atomic)
        return manifest
    }

    /// Sinh danh sách nguồn Core ML từ `manifest.json`: mọi file thuộc 8 gói `.mlpackage`.
    func coreMLSources(manifest: CoreMLManifest) -> [Source] {
        var list: [Source] = []
        for name in VieNeuModelStore.coreMLPackageNames {
            let prefix = "mlpackage/\(name).mlpackage/"
            for file in manifest.files where file.path.hasPrefix(prefix) {
                let relative = String(file.path.dropFirst(prefix.count))
                let destination = store.coreMLPackageURL(for: name).appendingPathComponent(relative)
                guard let url = URL(string: "\(Self.coreMLBase)/\(file.path)") else { continue }
                list.append(Source(
                    name: "\(name)/\(relative)",
                    url: url,
                    localURL: destination,
                    expectedSha: file.sha256,
                    expectedBytes: Int64(file.bytes)
                ))
            }
        }
        return list
    }

    /// Sinh danh sách nguồn **golden** từ `manifest.json`: 3 file `golden/T{n}.npz` theo lưới bucket.
    /// Dùng để tự test Core ML (so tham chiếu ORT fp32) sau khi biên dịch xong.
    func coreMLGoldenSources(manifest: CoreMLManifest) -> [Source] {
        var list: [Source] = []
        for frames in VieNeuBucketSelector.bucketFrames {
            let path = "golden/T\(frames).npz"
            guard let file = manifest.files.first(where: { $0.path == path }) else { continue }
            let destination = store.coreMLGoldenURL(for: frames)
            guard let url = URL(string: "\(Self.coreMLBase)/\(path)") else { continue }
            list.append(Source(
                name: path,
                url: url,
                localURL: destination,
                expectedSha: file.sha256,
                expectedBytes: Int64(file.bytes)
            ))
        }
        return list
    }

    private func downloadAll(
        _ all: [Source],
        progressHandler: ((String, Double) -> Void)?
    ) async throws -> Int {
        let background = BackgroundTaskSession.begin(name: "FreeBook-VieNeuModel")
        defer { background.end() }

        var downloaded = 0
        for (index, source) in all.enumerated() {
            let fraction = Double(index) / Double(all.count)
            if FileManager.default.fileExists(atPath: source.localURL.path) {
                progressHandler?("Đã có \(source.name)", fraction)
                continue
            }
            progressHandler?("Đang tải \(source.name)…", fraction)
            try await download(source)
            downloaded += 1
            progressHandler?("Xong \(source.name)", Double(index + 1) / Double(all.count))
        }
        progressHandler?("Tải xong", 1.0)
        return downloaded
    }

    /// Tải một file qua hai bước move: `URLSession` trả file ở thư mục tạm của hệ thống (có thể khác
    /// volume, nên bước này là copy+delete chứ không nguyên tử), rồi `staging → destination` **cùng thư
    /// mục** — chỉ bước cuối mới cần nguyên tử, và chỉ nó mới nguyên tử. Nhờ vậy `store.exists(name)`
    /// không bao giờ thấy một file `.onnx` cụt.
    private func download(_ source: Source) async throws {
        let destination = source.localURL
        let staging = destination.appendingPathExtension("partial")

        let (temporary, response) = try await session.download(from: source.url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.httpStatus(source.name, http.statusCode)
        }
        let size = ((try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 0 else { throw DownloadError.emptyBody(source.name) }

        // Kiểm SHA-256 nếu có (Core ML). Làm trên file tạm trước khi move để không ghi file sai SHA ra đĩa.
        if let expected = source.expectedSha {
            let got = Self.sha256(of: temporary)
            guard got.caseInsensitiveCompare(expected) == .orderedSame else {
                throw DownloadError.shaMismatch(source.name, got, expected)
            }
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination.deletingLastPathComponent(),
                                        withIntermediateDirectories: true)
        try? fileManager.removeItem(at: staging)
        try fileManager.moveItem(at: temporary, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
    }

    /// Xoá 8 file lõi **và** gói graph clone (nếu có). Xem `VieNeuModelStore.deleteAll` để biết vì sao
    /// xoá từng file chứ không xoá cây, và vì sao giọng user **không** bị đụng.
    func deleteAll() throws {
        try store.deleteAll()
    }

    // MARK: - SHA-256

    private static func sha256(of url: URL) -> String {
        var hasher = SHA256()
        if let stream = InputStream(url: url) {
            stream.open()
            defer { stream.close() }
            let bufferSize = 1 << 16
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 { break }
                hasher.update(buffer[..<read])
            }
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Core ML manifest (nested: giữ 1 type chính mỗi file)

    /// `manifest.json` của repo Core ML — sha256 + size từng file. App kiểm size lúc tải (hiện tại chỉ kiểm `size > 0`).
    struct CoreMLManifest: Codable {
        let files: [CoreMLManifestFile]
        let modelRevision: String?
        let buckets: [Int]?
        let length: Int?
        /// Tổng byte các gói (bao gồm `.mlpackage` chưa biên dịch).
        let totalBytes: Int?

        enum CodingKeys: String, CodingKey {
            case files, modelRevision, buckets, length
            case totalBytes = "totalBytes"
        }
    }

    /// Một mục file trong `manifest.json`.
    struct CoreMLManifestFile: Codable {
        /// Đường dẫn tương đối so với gốc repo, ví dụ `mlpackage/text_encoder.mlpackage/Data/com.apple.coreml/…/model.mlmodel`.
        let path: String
        let bytes: Int
        let sha256: String
    }
}
