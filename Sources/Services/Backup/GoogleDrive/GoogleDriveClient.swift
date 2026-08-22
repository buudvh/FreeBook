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
    /// **task delegate** (`didWriteData`) — API async không trả về `URLSessionTask` nên không có
    /// đường nào khác để đọc số byte đã nhận.
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

    /// Chỉ cài đúng `didWriteData`. **Không** cài `didFinishDownloadingTo`: bản async của
    /// `download(for:delegate:)` tự dời file tạm, cài thêm hàm đó là tranh chấp với nó.
    ///
    /// Delegate được gọi trên queue của `URLSession`, và mỗi lần có gói dữ liệu về là một lần gọi,
    /// nên chỉ báo khi **phần trăm đổi** — không thì hàng nghìn cập nhật sẽ dội lên MainActor.
    private final class DownloadProgressObserver: NSObject, URLSessionDownloadDelegate {
        private let name: String
        private let fallbackTotal: Int64
        private let report: @Sendable (BackupProgress) -> Void
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

        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didWriteData bytesWritten: Int64,
            totalBytesWritten: Int64,
            totalBytesExpectedToWrite: Int64
        ) {
            // Drive có thể không gửi `Content-Length`; khi đó dùng dung lượng lấy từ danh sách file.
            let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : fallbackTotal
            guard total > 0 else { return }

            let percent = Int(min(100, Double(totalBytesWritten) / Double(total) * 100))
            guard percent != lastPercent else { return }
            lastPercent = percent

            report(BackupProgress(
                phase: .downloading,
                completedUnits: percent,
                totalUnits: 100,
                detail: name
            ))
        }

        /// Bắt buộc có vì protocol yêu cầu, nhưng cố ý để trống — xem ghi chú ở đầu type.
        func urlSession(
            _ session: URLSession,
            downloadTask: URLSessionDownloadTask,
            didFinishDownloadingTo location: URL
        ) {}
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
