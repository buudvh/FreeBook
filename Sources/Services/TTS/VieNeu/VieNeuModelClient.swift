import Foundation

/// Tải 8 file lõi của **VieNeu-TTS v3 Nano** về `VieNeuModelStore` (và, khi được yêu cầu riêng, cả 3
/// graph clone giọng — xem `prefetchCloneGraphs`).
///
/// ## Ghim sha, không lấy `main`
/// Model card của tác giả cảnh báo thẳng là "weights, voices and defaults may change between
/// revisions" — và việc đó **đã xảy ra một lần**: repo `VieNeu-TTS-v3-Nano` từng chứa graph
/// autoregressive (bản dùng trong `VieNeuTTS-Offline`), nay đã đổi sang flow-matching. Vì vậy mọi file
/// đều tải theo URL có sha. Từ 1.3.888 nguồn là **kho mirror** `VieNeuModelMirror` (ghim commit): bản
/// sao nguyên văn của các revision đã ghim trước đó, nên upstream sửa hay xoá file cũng không ảnh hưởng.
///
/// ## Không resume theo byte — cố ý, và đây là điểm lệch plan
/// Plan §4 bước 3 ghi "resume được". Bản này chỉ resume ở **mức từng file**: mỗi file tải vào một file
/// tạm rồi `moveItem` nguyên tử, nên một lượt tải đứt giữa chừng **không** làm hỏng file đã xong và lần
/// chạy sau chỉ tải lại đúng file còn thiếu. Resume theo byte (HTTP `Range` + `URLSession.resumeData`)
/// không làm được với `URLSession.download(from:)` của API async hiện tại, còn `URLSession.bytes(for:)`
/// thì trả từng byte một — 280 MB là không dùng được. Cách làm ở đây **giống hệt** `NghiTTSClient`
/// (`NghiTTSClient.swift:104-155`) nên không tạo ra mô hình tải thứ hai trong app.
final class VieNeuModelClient {
    /// URL trong kho mirror của một file theo **tên** trong `VieNeuModelStore` — `VieNeuModelMirror.nanoStorePath`
    /// chọn thư mục: `sea_g2p.bin`, `speaker_encoder.onnx`, `denoiser.onnx` (dùng chung với Turbo) ở `common/`, còn lại ở
    /// `nano/`:
    /// graph / cấu hình = bản sao `pnnbao-ump/VieNeu-TTS-v3-Nano` @ `aba295eb96a6fa6003ebe417cc1f2802a7adc1dc`,
    /// `voices_v3_nano.json` = bản sao `pnnbao97/VieNeu-TTS` @ `2e982ff857bbe23fffa0c314e0f60da2497e2f4b`,
    /// `sea_g2p.bin` (62.829.820 byte) = bản sao `pnnbao97/sea-g2p` @ `e825173f235d08ea19315b2b279fb11153b44cea`.
    /// Chuỗi rỗng khi URL hỏng ⇒ `source(name:urlString:)` ném `badURL`.
    private static func fileURL(_ name: String) -> String {
        VieNeuModelMirror.url(path: VieNeuModelMirror.nanoStorePath(name))?.absoluteString ?? ""
    }

    struct Source: Sendable {
        let name: String
        let url: URL
    }

    enum DownloadError: LocalizedError {
        case badURL(String)
        case httpStatus(String, Int)
        case emptyBody(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let name): return "URL không hợp lệ cho \(name)"
            case .httpStatus(let name, let code): return "Tải \(name) thất bại: HTTP \(code)"
            case .emptyBody(let name): return "Tải \(name) thất bại: nội dung rỗng"
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
    static func sources() throws -> [Source] {
        var list: [Source] = []
        for name in VieNeuModelStore.graphNames + VieNeuModelStore.configNames + VieNeuModelStore.assetNames {
            list.append(try source(name: name, urlString: fileURL(name)))
        }
        return list
    }

    /// Ba nguồn của **gói graph clone** (~91 MB), cùng kho và cùng commit với 4 graph chính
    /// (`speaker_encoder.onnx` ở `common/` vì Turbo cũng dùng).
    ///
    /// Tải **riêng** khỏi `sources()`: gói này là tuỳ chọn (chỉ cần khi tạo giọng mới) nên không được
    /// nằm trong `VieNeuModelStore.requiredNames` — xem doc của `cloneGraphNames`.
    static func cloneSources() throws -> [Source] {
        try VieNeuModelStore.cloneGraphNames.map {
            try source(name: $0, urlString: fileURL($0))
        }
    }

    /// Hai nguồn của **gói nhân bản giọng Turbo** (1.3.892): `speaker_encoder.onnx` + `denoiser.onnx`, cả hai ở `common/`
    /// của kho mirror. File đã có (vd `speaker_encoder.onnx` của gói clone Nano) thì `downloadAll` bỏ qua.
    static func turboCloneSources() throws -> [Source] {
        try VieNeuModelStore.turboCloneGraphNames.map {
            try source(name: $0, urlString: fileURL($0))
        }
    }

    private static func source(name: String, urlString: String) throws -> Source {
        guard let url = URL(string: urlString) else { throw DownloadError.badURL(name) }
        return Source(name: name, url: url)
    }

    /// Tải mọi file còn thiếu. Trả về số file **thực sự tải** trong lượt này.
    ///
    /// `progressHandler` nhận `(tên file, tiến độ 0…1)` — tiến độ ở **mức file**, không theo byte, đúng
    /// khuôn `NghiTTSClient.prefetchModels`.
    @discardableResult
    func prefetch(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        try await downloadAll(try Self.sources(), progressHandler: progressHandler)
    }

    /// Tải **gói graph clone** (3 file, ~91 MB). Cùng khuôn tiến độ với `prefetch`.
    @discardableResult
    func prefetchCloneGraphs(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        try await downloadAll(try Self.cloneSources(), progressHandler: progressHandler)
    }

    /// Tải **gói nhân bản giọng Turbo** (2 file, ~71 MB). Cùng khuôn tiến độ với `prefetch`.
    @discardableResult
    func prefetchTurboCloneGraphs(progressHandler: ((String, Double) -> Void)? = nil) async throws -> Int {
        try await downloadAll(try Self.turboCloneSources(), progressHandler: progressHandler)
    }

    private func downloadAll(
        _ all: [Source],
        progressHandler: ((String, Double) -> Void)?
    ) async throws -> Int {
        let background = BackgroundTaskSession.begin(name: "TangCongCac-VieNeuModel")
        defer { background.end() }

        var downloaded = 0
        for (index, source) in all.enumerated() {
            let fraction = Double(index) / Double(all.count)
            if store.exists(source.name) {
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
        let destination = store.url(for: source.name)
        let staging = destination.appendingPathExtension("partial")

        let (temporary, response) = try await session.download(from: source.url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw DownloadError.httpStatus(source.name, http.statusCode)
        }
        let size = ((try? temporary.resourceValues(forKeys: [.fileSizeKey]))?.fileSize) ?? 0
        guard size > 0 else { throw DownloadError.emptyBody(source.name) }

        let fileManager = FileManager.default
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
}
