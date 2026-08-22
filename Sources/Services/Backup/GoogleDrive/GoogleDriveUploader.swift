import Foundation

/// Upload `.fbbackup` lên Drive bằng **resumable upload**: file có thể vài trăm MB nên không thể
/// nạp hết vào RAM, và mạng di động đứt giữa đường thì chỉ mất một chunk.
public actor GoogleDriveUploader {
    public static let shared = GoogleDriveUploader()

    public enum Failure: LocalizedError {
        case http(Int)
        case missingSessionURL
        case fileUnreadable

        public var errorDescription: String? {
            switch self {
            case .http(let status):
                return "Google Drive từ chối upload (HTTP \(status))"
            case .missingSessionURL:
                return "Google Drive không trả về địa chỉ upload"
            case .fileUnreadable:
                return "Không đọc được file sao lưu"
            }
        }
    }

    private let chunkSize: Int64 = 8 * 1024 * 1024
    private let maxRetries = 3

    private init() {}

    public func upload(
        fileURL: URL,
        report: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) async throws -> GoogleDriveFile {
        let total = BackupPaths.fileSize(at: fileURL)
        guard total > 0 else { throw Failure.fileUnreadable }

        let name = fileURL.lastPathComponent
        let sessionURL = try await startSession(name: name, byteCount: total)
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var offset: Int64 = 0
        while offset < total {
            let length = Int(min(chunkSize, total - offset))
            try handle.seek(toOffset: UInt64(offset))
            guard let chunk = try handle.read(upToCount: length), !chunk.isEmpty else {
                throw Failure.fileUnreadable
            }

            report(BackupProgress(
                phase: .uploading,
                completedUnits: Int(offset / 1024),
                totalUnits: Int(total / 1024),
                detail: name
            ))

            let step = try await send(
                chunk: chunk,
                to: sessionURL,
                offset: offset,
                total: total
            )
            switch step {
            case .completed(let file):
                report(BackupProgress(phase: .finished, detail: name))
                AppLogger.shared.log("☁️ [Drive] Đã tải lên \(file.name) — \(file.displaySize)")
                return file
            case .continueFrom(let next):
                offset = max(next, offset + Int64(chunk.count))
            }
        }

        // Hết byte mà Drive chưa xác nhận: coi là lỗi để người dùng thử lại, không báo thành công giả.
        throw Failure.missingSessionURL
    }

    // MARK: - Các bước

    private enum Step {
        case completed(GoogleDriveFile)
        case continueFrom(Int64)
    }

    private func startSession(name: String, byteCount: Int64) async throws -> URL {
        let folder = try await GoogleDriveClient.shared.folderId()
        var components = URLComponents(string: GoogleDriveConfiguration.uploadEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "uploadType", value: "resumable"),
            URLQueryItem(name: "fields", value: "id,name,size,createdTime")
        ]

        let token = try await GoogleDriveAuthService.shared.accessToken()
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "X-Upload-Content-Type")
        request.setValue("\(byteCount)", forHTTPHeaderField: "X-Upload-Content-Length")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": [folder]
        ])
        request.timeoutInterval = 60

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.missingSessionURL }
        guard (200..<300).contains(http.statusCode) else { throw Failure.http(http.statusCode) }
        guard let location = http.value(forHTTPHeaderField: "Location"), let url = URL(string: location) else {
            throw Failure.missingSessionURL
        }
        return url
    }

    private func send(chunk: Data, to sessionURL: URL, offset: Int64, total: Int64) async throws -> Step {
        let end = offset + Int64(chunk.count) - 1
        var attempt = 0

        while true {
            var request = URLRequest(url: sessionURL)
            request.httpMethod = "PUT"
            request.setValue("bytes \(offset)-\(end)/\(total)", forHTTPHeaderField: "Content-Range")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300
            // Session URI đã mang upload_id, nhưng gắn thêm token cho chắc: upload dài có thể
            // vắt qua thời điểm access token cũ hết hạn.
            if let token = try? await GoogleDriveAuthService.shared.accessToken() {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }

            do {
                let (data, response) = try await URLSession.shared.upload(for: request, from: chunk)
                guard let http = response as? HTTPURLResponse else { throw Failure.missingSessionURL }

                switch http.statusCode {
                case 200, 201:
                    let raw = try JSONDecoder().decode(GoogleDriveFile.RawEntry.self, from: data)
                    return .completed(GoogleDriveFile.make(from: raw))
                case 308:
                    return .continueFrom(Self.nextOffset(from: http) ?? (end + 1))
                case 500...599:
                    try await backOff(&attempt)
                default:
                    throw Failure.http(http.statusCode)
                }
            } catch let failure as Failure {
                throw failure
            } catch {
                try await backOff(&attempt, underlying: error)
            }
        }
    }

    /// Tăng số lần thử; hết lượt thì ném lỗi thật thay vì quay vòng vô hạn.
    private func backOff(_ attempt: inout Int, underlying: Error? = nil) async throws {
        attempt += 1
        guard attempt <= maxRetries else {
            throw underlying ?? Failure.http(503)
        }
        try? await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
    }

    /// Drive trả `Range: bytes=0-<byte cuối đã nhận>` khi còn thiếu.
    private static func nextOffset(from response: HTTPURLResponse) -> Int64? {
        guard let range = response.value(forHTTPHeaderField: "Range"),
              let dashIndex = range.lastIndex(of: "-")
        else { return nil }
        let tail = range[range.index(after: dashIndex)...]
        guard let last = Int64(tail) else { return nil }
        return last + 1
    }
}
