import Foundation

/// Gửi backup qua Telegram Bot API. File lớn được chia streaming; các part gửi trước, manifest gửi cuối.
public actor TelegramBackupUploader {
    public static let shared = TelegramBackupUploader()

    public struct Outcome: Sendable {
        public let documentCount: Int
        public let wasSplit: Bool
    }

    public enum Failure: LocalizedError {
        case notConfigured
        case unreadable
        case invalidResponse
        case rejected(String)

        public var errorDescription: String? {
            switch self {
            case .notConfigured: return "Chưa cấu hình Telegram Bot"
            case .unreadable: return "Không đọc được file sao lưu"
            case .invalidResponse: return "Telegram trả về dữ liệu không hợp lệ"
            case .rejected(let message): return "Telegram từ chối: \(message)"
            }
        }
    }

    private struct Envelope: Decodable {
        struct Parameters: Decodable {
            let retryAfter: Int?

            enum CodingKeys: String, CodingKey {
                case retryAfter = "retry_after"
            }
        }
        let ok: Bool
        let description: String?
        let parameters: Parameters?

        enum CodingKeys: String, CodingKey {
            case ok, description, parameters
        }
    }

    private let maxRetries = 3
    private init() {}

    public func upload(
        fileURL: URL,
        report: @escaping @Sendable (BackupProgress) -> Void = { _ in }
    ) async throws -> Outcome {
        guard let token = TelegramTokenStore.load(), !TelegramConfiguration.chatID.isEmpty else {
            throw Failure.notConfigured
        }
        let size = BackupPaths.fileSize(at: fileURL)
        guard size > 0 else { throw Failure.unreadable }
        if size <= BackupMultipartArchive.defaultPartSize {
            try await sendDocument(fileURL, token: token, caption: "FreeBook backup", report: report)
            return Outcome(documentCount: 1, wasSplit: false)
        }

        let package = try BackupMultipartArchive.split(archive: fileURL)
        defer { package.cleanUp() }
        for (offset, part) in package.partURLs.enumerated() {
            report(BackupProgress(
                phase: .uploading,
                completedUnits: offset,
                totalUnits: package.partURLs.count + 1,
                detail: "Phần \(offset + 1)/\(package.partURLs.count)"
            ))
            try await sendDocument(part, token: token, caption: nil, report: { _ in })
        }
        try await sendDocument(
            package.manifestURL,
            token: token,
            caption: "Manifest hoàn tất. Tải manifest và toàn bộ part để khôi phục.",
            report: { _ in }
        )
        report(BackupProgress(phase: .finished, detail: package.manifestURL.lastPathComponent))
        return Outcome(documentCount: package.partURLs.count + 1, wasSplit: true)
    }

    private func sendDocument(
        _ fileURL: URL,
        token: String,
        caption: String?,
        report: @escaping @Sendable (BackupProgress) -> Void
    ) async throws {
        let boundary = "FreeBook-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("telegram-body-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        try makeMultipartBody(fileURL: fileURL, destination: bodyURL, boundary: boundary, caption: caption)

        var attempt = 0
        while true {
            var request = URLRequest(url: URL(string: "https://api.telegram.org/bot\(token)/sendDocument")!)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 300
            do {
                let (data, response) = try await URLSession.shared.upload(for: request, fromFile: bodyURL)
                guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
                let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
                if (500...599).contains(http.statusCode) {
                    try await backOff(&attempt)
                    continue
                }
                guard let envelope else { throw Failure.invalidResponse }
                if envelope.ok && (200..<300).contains(http.statusCode) {
                    report(BackupProgress(phase: .finished, detail: fileURL.lastPathComponent))
                    return
                }
                if http.statusCode == 429 {
                    attempt += 1
                    guard attempt <= maxRetries else { throw Failure.rejected(envelope.description ?? "HTTP 429") }
                    let delay = max(envelope.parameters?.retryAfter ?? attempt, 1)
                    try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                    continue
                }
                throw Failure.rejected(envelope.description ?? "HTTP \(http.statusCode)")
            } catch let failure as Failure {
                throw failure
            } catch {
                try await backOff(&attempt, underlying: error)
            }
        }
    }

    private func makeMultipartBody(fileURL: URL, destination: URL, boundary: String, caption: String?) throws {
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }

        func write(_ text: String) throws {
            guard let data = text.data(using: .utf8) else { throw Failure.unreadable }
            try output.write(contentsOf: data)
        }
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n")
        try write(TelegramConfiguration.chatID + "\r\n")
        if let caption {
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n")
            try write(caption + "\r\n")
        }
        let safeName = fileURL.lastPathComponent.replacingOccurrences(of: "\"", with: "_")
        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"document\"; filename=\"\(safeName)\"\r\n")
        try write("Content-Type: application/octet-stream\r\n\r\n")
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let data = try input.read(upToCount: 1024 * 1024), !data.isEmpty {
            try output.write(contentsOf: data)
        }
        try write("\r\n--\(boundary)--\r\n")
    }

    private func backOff(_ attempt: inout Int, underlying: Error? = nil) async throws {
        attempt += 1
        guard attempt <= maxRetries else { throw underlying ?? Failure.rejected("Hết số lần thử") }
        try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
    }
}
