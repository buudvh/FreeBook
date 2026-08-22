import Foundation

/// Gọi Drive v3 cho thư mục `FreeBookBackups`. Scope `drive.file` nên client chỉ thấy được
/// đúng những file do app này tạo — đó là lý do không cần quyền đọc toàn bộ Drive.
public actor GoogleDriveClient {
    public static let shared = GoogleDriveClient()

    public enum Failure: LocalizedError {
        case http(Int)
        case invalidResponse

        public var errorDescription: String? {
            switch self {
            case .http(let status):
                return "Google Drive trả về lỗi HTTP \(status)"
            case .invalidResponse:
                return "Google Drive trả về dữ liệu không đọc được"
            }
        }
    }

    private var cachedFolderId: String?

    private init() {}

    public func resetCache() {
        cachedFolderId = nil
    }

    /// Tìm thư mục `FreeBookBackups`, chưa có thì tạo.
    public func folderId() async throws -> String {
        if let cachedFolderId { return cachedFolderId }

        let query = "mimeType='application/vnd.google-apps.folder'"
            + " and name='\(GoogleDriveConfiguration.folderName)' and trashed=false"
        var components = URLComponents(string: GoogleDriveConfiguration.filesEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "fields", value: "files(id,name)"),
            URLQueryItem(name: "pageSize", value: "10")
        ]

        let data = try await send(makeRequest(url: components.url!))
        let decoded = try JSONDecoder().decode(GoogleDriveFile.ListResponse.self, from: data)
        if let existing = decoded.files?.first?.id {
            cachedFolderId = existing
            return existing
        }
        return try await createFolder()
    }

    public func listBackups() async throws -> [GoogleDriveFile] {
        let folder = try await folderId()
        var components = URLComponents(string: GoogleDriveConfiguration.filesEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "'\(folder)' in parents and trashed=false"),
            URLQueryItem(name: "fields", value: "files(id,name,size,createdTime)"),
            URLQueryItem(name: "orderBy", value: "createdTime desc"),
            URLQueryItem(name: "pageSize", value: "100")
        ]

        let data = try await send(makeRequest(url: components.url!))
        let decoded = try JSONDecoder().decode(GoogleDriveFile.ListResponse.self, from: data)
        return (decoded.files ?? [])
            .filter { $0.name.lowercased().hasSuffix(".\(BackupPaths.fileExtension)") }
            .map { GoogleDriveFile.make(from: $0) }
    }

    public func delete(fileId: String) async throws {
        let url = URL(string: "\(GoogleDriveConfiguration.filesEndpoint)/\(fileId)")!
        var deleteRequest = try await makeRequest(url: url)
        deleteRequest.httpMethod = "DELETE"
        _ = try await send(deleteRequest)
    }

    /// Tải về thư mục tạm; **người gọi tự dọn** thư mục cha của URL trả về.
    ///
    /// Dùng `URLSession.download(for:)` chứ không stream từng byte: archive có thể vài trăm MB,
    /// vòng lặp `for await byte in` sẽ chậm hơn nhiều lần và giữ RAM vô ích. Tiến độ lấy qua
    /// **task delegate** — xem `DownloadProgressObserver` để biết vì sao phải đi qua `didCreateTask`
    /// + KVO thay vì `didWriteData`.
    public func download(
        file: GoogleDriveFile,
        report: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) async throws -> URL {
        var components = URLComponents(string: "\(GoogleDriveConfiguration.filesEndpoint)/\(file.id)")!
        components.queryItems = [URLQueryItem(name: "alt", value: "media")]

        // Giữ mạnh tới hết lời gọi: `download(for:delegate:)` chỉ giữ delegate yếu.
        let observer = DownloadProgressObserver(
            name: file.name,
            fallbackTotal: file.byteCount,
            report: report
        )
        let (temporaryURL, response) = try await URLSession.shared.download(
            for: try await makeRequest(url: components.url!),
            delegate: observer
        )
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw Failure.http(status)
        }

        let directory = try BackupPaths.makeWorkingDirectory(prefix: "fb-backup-download")
        let target = directory.appendingPathComponent(file.name)
        do {
            try FileManager.default.moveItem(at: temporaryURL, to: target)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
        return target
    }

    // MARK: - Tiến độ tải xuống

    /// Bản async của `download(for:delegate:)` **không** gọi `URLSessionDownloadDelegate`: nó dựng
    /// trên completion handler nên mọi callback tải xuống bị chặn, và tham số `delegate:` còn khai
    /// kiểu `URLSessionTaskDelegate` nên `didWriteData` không nằm trong tập được gọi.
    ///
    /// Đường còn lại (Apple DTS đề nghị): `didCreateTask` **vẫn** được gọi ⇒ bám vào `task.progress`
    /// bằng KVO. Vẫn không stream từng byte: archive có thể vài trăm MB, vòng lặp `for await byte in`
    /// sẽ chậm hơn nhiều lần và giữ RAM vô ích.
    ///
    /// Chỉ báo khi **phần trăm đổi** — KVO nổ theo từng gói dữ liệu, không tiết chế thì hàng nghìn
    /// cập nhật sẽ dội lên MainActor.
    private final class DownloadProgressObserver: NSObject, URLSessionTaskDelegate {
        private let name: String
        private let fallbackTotal: Int64
        private let report: @Sendable (BackupProgress) -> Void
        private var observations: [NSKeyValueObservation] = []
        private var lastPercent = -1

        init(
            name: String,
            fallbackTotal: Int64,
            report: @escaping @Sendable (BackupProgress) -> Void
        ) {
            self.name = name
            self.fallbackTotal = fallbackTotal
            self.report = report
        }

        deinit {
            observations.forEach { $0.invalidate() }
        }

        /// Callback duy nhất còn sống ở đường async — nơi duy nhất lấy được `URLSessionTask`.
        func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
            let progress = task.progress
            // Bám hai khoá: `fractionCompleted` là khoá KVO chính thức của `Progress`, còn
            // `completedUnitCount` phủ trường hợp thiếu `Content-Length` (lúc đó `totalUnitCount`
            // là -1 nên `fractionCompleted` đứng im ở 0 và sẽ không phát tín hiệu nào).
            observations = [
                progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] value, _ in
                    self?.emit(completed: value.completedUnitCount, expected: value.totalUnitCount)
                },
                progress.observe(\.completedUnitCount, options: [.new]) { [weak self] value, _ in
                    self?.emit(completed: value.completedUnitCount, expected: value.totalUnitCount)
                }
            ]
        }

        private func emit(completed: Int64, expected: Int64) {
            // Drive có thể không gửi `Content-Length`; khi đó dùng dung lượng lấy từ danh sách file.
            let total = expected > 0 ? expected : fallbackTotal
            guard total > 0 else { return }

            let percent = Int(min(100, max(0, Double(completed) / Double(total) * 100)))
            guard percent != lastPercent else { return }
            lastPercent = percent

            report(BackupProgress(
                phase: .downloading,
                completedUnits: percent,
                totalUnits: 100,
                detail: name
            ))
        }
    }

    // MARK: - Hạ tầng

    private func createFolder() async throws -> String {
        var createRequest = try await makeRequest(url: URL(string: GoogleDriveConfiguration.filesEndpoint)!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": GoogleDriveConfiguration.folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])

        let data = try await send(createRequest)
        let created = try JSONDecoder().decode(GoogleDriveFile.CreateResponse.self, from: data)
        cachedFolderId = created.id
        AppLogger.shared.log("☁️ [Drive] Đã tạo thư mục \(GoogleDriveConfiguration.folderName)")
        return created.id
    }

    private func makeRequest(url: URL) async throws -> URLRequest {
        let token = try await GoogleDriveAuthService.shared.accessToken()
        var built = URLRequest(url: url)
        built.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        built.timeoutInterval = 60
        return built
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        return data
    }
}
