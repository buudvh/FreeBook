import Foundation

/// Tải bộ model VieNeu-TTS v3 Turbo (~274 MB) về `VieNeuModelStore`.
///
/// Ba điểm khác `NghiTTSClient.prefetchModels`, đều vì kích thước:
///
/// 1. **Resume bằng HTTP Range.** 274 MB trên mạng di động gần như chắc chắn bị ngắt. Mỗi file
///    tải vào `<tên>.part`; lần sau gửi `Range: bytes=<đã có>-` và **nối tiếp** thay vì tải lại.
///    Chọn Range thay vì `URLSessionConfiguration.background` vì background session bắt buộc
///    dùng delegate, không await được, và cần một singleton sống ngoài vòng đời View.
/// 2. **Nguyên tử ở mức cả bộ.** Tải vào thư mục staging; chỉ khi đủ 11 file và mỗi file đạt cỡ
///    tối thiểu mới đổi tên thành thư mục thật. Bộ tải dở không bao giờ trông như đã cài.
/// 3. **Progress theo byte tổng**, không phải "xong file thứ mấy" — một file 104 MB đứng cạnh một
///    file 500 byte thì đếm theo file là vô nghĩa.
final class VieNeuModelDownloader: @unchecked Sendable {
    struct Progress: Sendable {
        let message: String
        let fraction: Double
        let bytesDone: Int64
        let bytesTotal: Int64
    }

    private struct Source {
        let file: VieNeuModelFile
        let url: URL
        /// Cỡ dự kiến, chỉ dùng làm mẫu số cho progress. Sai vài phần trăm không sao.
        let expectedBytes: Int64
    }

    private static let modelRepo = "https://huggingface.co/pnnbao-ump/VieNeu-TTS-v3-Turbo/resolve/main"
    private static let codecRepo = "https://huggingface.co/OpenMOSS-Team/MOSS-Audio-Tokenizer-Nano-ONNX/resolve/main"
    private static let seaG2PRepo = "https://raw.githubusercontent.com/pnnbao97/sea-g2p/main/python/sea_g2p"
    private static let vieneuSDKRepo = "https://raw.githubusercontent.com/pnnbao97/VieNeu-TTS/main/src/vieneu/assets"

    /// **Bắt buộc là `onnx_int8`, không phải `onnx`.**
    ///
    /// Backbone fp32 ở thư mục `onnx/` nặng 415 MB; decode step đo trên iPhone 11 mất 19.92 ms
    /// cho mỗi frame, tức 20.8 GB/s — nó thuần bị chặn bởi băng thông bộ nhớ. Bản int8 chỉ 104 MB
    /// nên hạng mục chiếm 64% vòng lặp giảm gần 4 lần. Đổi lại, kiến trúc `onnx_int8` khác
    /// `onnx` ở 4 chỗ (1 local layer, cần speaker embedding, heads fp32, style token 16) — xem
    /// `VieNeuDecodeLoop` và `VieNeuEmbeddingTables`.
    private static let onnxSubfolder = "onnx_int8"

    private let store: VieNeuModelStore

    init(store: VieNeuModelStore) {
        self.store = store
    }

    private static func sources() -> [Source] {
        [
            Source(file: .prefill, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/vieneu_prefill.onnx")!, expectedBytes: 1_090_823),
            Source(file: .decodeStep, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/vieneu_decode_step.onnx")!, expectedBytes: 1_062_040),
            Source(file: .acoustic, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/vieneu_acoustic_cached.onnx")!, expectedBytes: 7_210_000),
            Source(file: .backboneData, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/vieneu_backbone_shared.data")!, expectedBytes: 104_000_000),
            Source(file: .heads, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/vieneu_v3_heads.npz")!, expectedBytes: 52_200_000),
            Source(file: .config, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/config.json")!, expectedBytes: 2_150),
            Source(file: .tokenizer, url: URL(string: "\(modelRepo)/\(onnxSubfolder)/tokenizer.json")!, expectedBytes: 22_300),
            Source(file: .codecDecode, url: URL(string: "\(codecRepo)/moss_audio_tokenizer_decode_full.onnx")!, expectedBytes: 682_000),
            Source(file: .codecData, url: URL(string: "\(codecRepo)/moss_audio_tokenizer_decode_shared.data")!, expectedBytes: 44_200_000),
            Source(file: .seaG2P, url: URL(string: "\(seaG2PRepo)/sea_g2p.bin")!, expectedBytes: 62_829_820),
            Source(file: .voices, url: URL(string: "\(vieneuSDKRepo)/voices_v3_turbo.json")!, expectedBytes: 140_175)
        ]
    }

    static var totalExpectedBytes: Int64 {
        sources().reduce(Int64(0)) { $0 + $1.expectedBytes }
    }

    /// Tải toàn bộ bộ model. Idempotent: đã cài rồi thì trả về ngay.
    func download(progressHandler: @escaping @Sendable (Progress) -> Void) async throws {
        if store.isInstalled { return }

        let bgSession = BackgroundTaskSession.begin(name: "FreeBook-DownloadVieNeu")
        defer { bgSession.end() }

        let fm = FileManager.default
        try fm.createDirectory(at: store.stagingDirectoryURL, withIntermediateDirectories: true)

        // Bộ đã cài nhưng thiếu vài file (ví dụ người dùng xoá tay): kéo file còn tốt sang staging
        // để không tải lại 104 MB một cách vô ích.
        for file in VieNeuModelFile.allCases {
            let installed = store.url(for: file)
            let staged = store.stagingURL(for: file)
            guard fm.fileExists(atPath: installed.path), !fm.fileExists(atPath: staged.path) else { continue }
            let size = (try? installed.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            if size >= file.minimumBytes {
                try? fm.copyItem(at: installed, to: staged)
            }
        }

        let sources = Self.sources()
        let total = Self.totalExpectedBytes
        var completedBytes: Int64 = 0

        for source in sources {
            let destination = store.stagingURL(for: source.file)
            if fm.fileExists(atPath: destination.path),
               ((try? destination.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) >= source.file.minimumBytes {
                completedBytes += source.expectedBytes
                progressHandler(Progress(
                    message: "Đã có \(source.file.rawValue)",
                    fraction: Double(completedBytes) / Double(total),
                    bytesDone: completedBytes,
                    bytesTotal: total
                ))
                continue
            }

            let baseBytes = completedBytes
            try await downloadResumable(source: source, to: destination) { fileBytes in
                let done = baseBytes + fileBytes
                progressHandler(Progress(
                    message: "Đang tải \(source.file.rawValue)…",
                    fraction: min(1.0, Double(done) / Double(total)),
                    bytesDone: done,
                    bytesTotal: total
                ))
            }
            completedBytes += source.expectedBytes
        }

        // Kiểm đủ **trong staging** trước khi đổi tên: nếu còn thiếu thì để nguyên staging cho
        // lần sau tiếp tục, không phá bộ đang cài (nếu có).
        let stagedMissing = VieNeuModelFile.allCases.filter { file in
            let url = store.stagingURL(for: file)
            guard fm.fileExists(atPath: url.path) else { return true }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return size < file.minimumBytes
        }
        guard stagedMissing.isEmpty else {
            let names = stagedMissing.map(\.rawValue).joined(separator: ", ")
            AppLogger.shared.log("🗣️ [VieNeuDownloader] Thiếu file sau khi tải: \(names)")
            throw TTSError.modelNotCached("Bộ model VieNeu tải chưa đủ, còn thiếu: \(names)")
        }

        try store.promoteStagingToInstalled()
        AppLogger.shared.log("🗣️ [VieNeuDownloader] Đã cài bộ model VieNeu (\(store.bytesInstalled()) byte)")
        progressHandler(Progress(message: "Tải hoàn tất", fraction: 1.0, bytesDone: total, bytesTotal: total))
    }

    /// Tải một file, nối tiếp phần đã có trong `<tên>.part`.
    ///
    /// Máy chủ không hỗ trợ Range sẽ trả 200 kèm **toàn bộ** nội dung thay vì 206; khi đó phải bỏ
    /// phần đã có và ghi lại từ đầu. Nối thẳng vào sẽ tạo ra file đúng cỡ nhưng sai nội dung — dạng
    /// hỏng khó nhận ra nhất, vì `ORTSession` sẽ chết bằng một thông báo chẳng liên quan.
    private func downloadResumable(
        source: Source,
        to destination: URL,
        onBytes: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let fm = FileManager.default
        let partURL = destination.appendingPathExtension("part")
        var existingBytes: Int64 = 0
        if fm.fileExists(atPath: partURL.path) {
            existingBytes = Int64((try? partURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }

        var request = URLRequest(url: source.url)
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }

        let alreadyHave = existingBytes
        let downloader = VieNeuFileDownload { written, _ in
            onBytes(alreadyHave + written)
        }
        let (temporaryURL, http) = try await downloader.run(request: request)
        defer { try? fm.removeItem(at: temporaryURL) }

        guard (200...299).contains(http.statusCode) else {
            throw TTSError.internalError("HTTP \(http.statusCode) khi tải \(source.file.rawValue)")
        }

        if http.statusCode == 206 && existingBytes > 0 {
            try Self.append(contentsOf: temporaryURL, to: partURL)
        } else {
            if fm.fileExists(atPath: partURL.path) { try fm.removeItem(at: partURL) }
            try fm.moveItem(at: temporaryURL, to: partURL)
        }

        let written = Int64((try? partURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        guard written >= Int64(source.file.minimumBytes) else {
            throw TTSError.internalError(
                "\(source.file.rawValue) chỉ tải được \(written) byte, nhỏ hơn ngưỡng \(source.file.minimumBytes)"
            )
        }

        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: partURL, to: destination)
        onBytes(written)
    }

    /// Nối nội dung `source` vào cuối `target` theo từng khối 4 MiB.
    ///
    /// Không đọc cả file vào RAM: phần nối của backbone có thể là hàng chục MB và app còn phải chừa
    /// bộ nhớ cho reader lẫn WKWebView của extension.
    private static func append(contentsOf source: URL, to target: URL) throws {
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }
        let writer = try FileHandle(forWritingTo: target)
        defer { try? writer.close() }
        try writer.seekToEnd()

        let chunkSize = 4 << 20
        while true {
            guard let chunk = try reader.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            try writer.write(contentsOf: chunk)
        }
    }
}
