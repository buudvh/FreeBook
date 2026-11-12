import Foundation

/// Tải file cho bước thử VieNeu Turbo: GGUF 188 MB, manifest giọng, cặp file của từng giọng, và `sea_g2p.bin` (khi
/// máy chưa có engine Nano).
///
/// Cùng khuôn ghi file với `VieNeuModelClient`: `URLSession` trả file tạm ⇒ chuyển sang `<đích>.partial` **cùng thư
/// mục** ⇒ `moveItem` nguyên tử thành file đích, nên kho không bao giờ thấy file cụt. Khác một điểm: GGUF là **một**
/// file 188 MB, tiến độ theo file (0 → 1) là vô nghĩa, nên ở đây báo **theo byte** bằng KVO `task.progress` — đúng
/// cách `GoogleDriveClient` làm (bản async của `download(for:delegate:)` không gọi `didWriteData`).
final class VieNeuTurboModelClient: Sendable {
    enum DownloadError: LocalizedError {
        case badURL(String)
        case httpStatus(String, Int)
        case emptyBody(String)
        case sizeMismatch(String, expected: Int64, actual: Int64)
        case missingG2PSource
        case customVoiceMissing(String)

        var errorDescription: String? {
            switch self {
            case .badURL(let name): return "URL không hợp lệ cho \(name)"
            case .httpStatus(let name, let code): return "Tải \(name) thất bại: HTTP \(code)"
            case .emptyBody(let name): return "Tải \(name) thất bại: nội dung rỗng"
            case .sizeMismatch(let name, let expected, let actual):
                return "Tải \(name) thất bại: được \(actual) byte, cần đúng \(expected) byte"
            case .missingG2PSource: return "Không tìm thấy nguồn tải sea_g2p.bin của VieNeu Nano"
            case .customVoiceMissing(let id): return "Giọng tự tạo \(id) không còn trên máy (đã xoá?)"
            }
        }
    }

    /// `(byte đã tải, tổng byte)`; tổng ≤ 0 khi máy chủ không báo `Content-Length`.
    typealias ByteProgress = @Sendable (Int64, Int64) -> Void

    private let store: VieNeuTurboModelStore
    private let session: URLSession

    init(store: VieNeuTurboModelStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    // MARK: - Các gói

    func downloadModel(progress: @escaping ByteProgress) async throws {
        guard let url = VieNeuTurboModelStore.remoteURL(path: VieNeuTurboModelStore.modelRemotePath) else {
            throw DownloadError.badURL(VieNeuTurboModelStore.modelFileName)
        }
        try await download(
            from: url,
            to: store.modelURL,
            name: VieNeuTurboModelStore.modelFileName,
            expectedBytes: VieNeuTurboModelStore.modelByteCount,
            progress: progress
        )
    }

    func downloadManifest() async throws {
        guard let url = VieNeuTurboModelStore.remoteURL(path: VieNeuTurboModelStore.manifestRemotePath) else {
            throw DownloadError.badURL(VieNeuTurboModelStore.manifestFileName)
        }
        try await download(from: url, to: store.manifestURL, name: VieNeuTurboModelStore.manifestFileName)
    }

    /// Cặp `ref_codes.txt` + `speaker.emb.txt` của một giọng (vài KB mỗi file). Có rồi thì bỏ qua.
    func downloadVoice(voiceId: String) async throws {
        guard VieNeuTurboModelStore.isSafeVoiceId(voiceId) else { throw DownloadError.badURL(voiceId) }
        // Giọng tự tạo không có trên kho mirror: thiếu file nghĩa là đã bị xoá — báo rõ thay vì HTTP 404.
        guard !VieNeuTurboModelStore.isCustomVoiceId(voiceId) else {
            if store.hasVoice(voiceId: voiceId) { return }
            throw DownloadError.customVoiceMissing(voiceId)
        }
        try FileManager.default.createDirectory(
            at: store.voiceDirectory(voiceId: voiceId),
            withIntermediateDirectories: true
        )
        let files = [
            (VieNeuTurboModelStore.referenceCodesFileName, store.referenceCodesURL(voiceId: voiceId)),
            (VieNeuTurboModelStore.speakerEmbeddingFileName, store.speakerEmbeddingURL(voiceId: voiceId))
        ]
        for (fileName, destination) in files where !FileManager.default.fileExists(atPath: destination.path) {
            let remotePath = VieNeuTurboModelStore.voiceRemotePath(voiceId: voiceId, fileName: fileName)
            guard let url = VieNeuTurboModelStore.remoteURL(path: remotePath) else {
                throw DownloadError.badURL(remotePath)
            }
            try await download(from: url, to: destination, name: "\(voiceId)/\(fileName)")
        }
    }

    /// `sea_g2p.bin` vào **đúng chỗ của Nano** (`VieNeuModelStore`), lấy URL ghim sha từ `VieNeuModelClient.sources()`
    /// — không khai nguồn thứ hai, không tải cả 343 MB của Nano chỉ vì cần bộ phiên âm.
    static func downloadG2PDictionary(to destination: URL, progress: @escaping ByteProgress) async throws {
        guard let source = try VieNeuModelClient.sources().first(where: { $0.name == "sea_g2p.bin" }) else {
            throw DownloadError.missingG2PSource
        }
        try await VieNeuTurboModelClient.transfer(
            session: .shared,
            from: source.url,
            to: destination,
            name: source.name,
            expectedBytes: nil,
            progress: progress
        )
    }

    // MARK: - Một file

    private func download(
        from url: URL,
        to destination: URL,
        name: String,
        expectedBytes: Int64? = nil,
        progress: ByteProgress? = nil
    ) async throws {
        try await Self.transfer(
            session: session,
            from: url,
            to: destination,
            name: name,
            expectedBytes: expectedBytes,
            progress: progress
        )
    }

    /// `internal` (không `private`) vì gói graph tĩnh của phép thử Nano (`VieNeuNanoStaticPackage`) tải cùng đường này.
    static func transfer(
        session: URLSession,
        from url: URL,
        to destination: URL,
        name: String,
        expectedBytes: Int64?,
        progress: ByteProgress?
    ) async throws {
        let background = BackgroundTaskSession.begin(name: "TangCongCac-VieNeuTurbo")
        defer { background.end() }

        // Giữ mạnh tới hết lời gọi: `download(for:delegate:)` chỉ giữ delegate yếu.
        let observer = ProgressObserver(fallbackTotal: expectedBytes ?? 0, report: progress)
        let (temporary, response) = try await session.download(for: URLRequest(url: url), delegate: observer)
        let fileManager = FileManager.default
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            try? fileManager.removeItem(at: temporary)
            throw DownloadError.httpStatus(name, http.statusCode)
        }
        let size = VieNeuTurboModelStore.fileSize(at: temporary)
        guard size > 0 else {
            try? fileManager.removeItem(at: temporary)
            throw DownloadError.emptyBody(name)
        }
        if let expectedBytes, size != expectedBytes {
            try? fileManager.removeItem(at: temporary)
            throw DownloadError.sizeMismatch(name, expected: expectedBytes, actual: size)
        }

        let staging = destination.appendingPathExtension("partial")
        try? fileManager.removeItem(at: staging)
        try fileManager.moveItem(at: temporary, to: staging)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        AppLogger.shared.log("🎙️ [VieNeuTurbo] Đã tải \(name) (\(size) byte)")
    }

    /// Bám `task.progress` qua `didCreateTask` — callback duy nhất còn sống ở đường async (xem doc của type).
    /// Chỉ báo khi **phần nghìn** đổi: KVO nổ theo từng gói dữ liệu, không tiết chế thì dội hàng nghìn lần lên MainActor.
    private final class ProgressObserver: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let fallbackTotal: Int64
        private let report: ByteProgress?
        private let lock = NSLock()
        private var observations: [NSKeyValueObservation] = []
        private var lastBucket = Int.min

        init(fallbackTotal: Int64, report: ByteProgress?) {
            self.fallbackTotal = fallbackTotal
            self.report = report
        }

        deinit {
            observations.forEach { $0.invalidate() }
        }

        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            guard report != nil else { return }
            let progress = task.progress
            let tokens = [
                progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                    self?.emit(completed: value.completedUnitCount, expected: value.totalUnitCount)
                },
                progress.observe(\.completedUnitCount, options: [.new]) { [weak self] value, _ in
                    self?.emit(completed: value.completedUnitCount, expected: value.totalUnitCount)
                }
            ]
            lock.lock()
            observations = tokens
            lock.unlock()
        }

        private func emit(completed: Int64, expected: Int64) {
            let total = expected > 0 ? expected : fallbackTotal
            // Biết tổng ⇒ theo phần nghìn; không biết ⇒ theo từng MiB đã tải.
            let bucket = total > 0
                ? Int(min(1_000, max(0, Double(completed) / Double(total) * 1_000)))
                : -1 - Int(completed >> 20)
            lock.lock()
            let changed = bucket != lastBucket
            lastBucket = bucket
            lock.unlock()
            guard changed else { return }
            report?(completed, total)
        }
    }
}
