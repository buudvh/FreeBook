import Foundation

/// Tải một file media lớn (mp4/mov/m4v) ra đĩa theo luồng (không giữ cả file trong RAM) vào `video.part`, xong thì đổi
/// tên thành `video.<đuôi>`. Bản dở cùng chữ ký nguồn ⇒ tải tiếp bằng `Range` (206 ⇒ nối; 200 ⇒ máy chủ không hỗ trợ,
/// ghi lại từ đầu). Đứt mạng giữa chừng ⇒ thử lại tối đa `VideoOfflineHTTPClient.maxAttempts` lượt, mỗi lượt tải tiếp.
///
/// Mỗi lần tải dùng một instance + một `URLSession` riêng (session giữ delegate mạnh tới khi invalidate).
final class VideoFileDownloader: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    enum FileError: LocalizedError {
        case notMedia(String)
        case incomplete(Int64, Int64)

        var errorDescription: String? {
            switch self {
            case .notMedia(let mime): return "Link tải trả về trang web (\(mime)), không phải file video."
            case .incomplete(let got, let expected): return "File video tải chưa đủ (\(got)/\(expected) byte)."
            }
        }
    }

    struct Outcome {
        let fileName: String
        let totalBytes: Int64
    }

    private static let partFileName = "video.part"
    private static let progressInterval: CFAbsoluteTime = 0.5

    private let lock = NSLock()
    private let progress: (Double, Int64) -> Void
    private var handle: FileHandle?
    private var received: Int64 = 0
    private var expected: Int64?
    private var mimeType: String?
    private var responseError: Error?
    private var responseChecked = false
    private var continuation: CheckedContinuation<Void, Error>?
    private var lastProgressAt: CFAbsoluteTime = 0

    init(progress: @escaping (Double, Int64) -> Void) {
        self.progress = progress
    }

    func download(url: URL, headers: [String: String], into directory: URL) async throws -> Outcome {
        let signature = "file\n\(url.scheme ?? "")://\(url.host ?? "")\(url.path)".sha256()
        let resumed = try VideoOfflineStore.beginPartial(in: directory, signature: signature)
        let partURL = directory.appendingPathComponent(Self.partFileName, isDirectory: false)
        if !FileManager.default.fileExists(atPath: partURL.path) {
            try VideoOfflineStore.writeAtomic(Data(), to: partURL)
        }
        AppLogger.shared.log("📥 [VideoOffline] Tải file \(VideoSourceResolution.redact(url))\(resumed ? " (tải tiếp bản dở)" : "")")

        var attempt = 1
        while true {
            do {
                try await transfer(url: url, headers: headers, partURL: partURL)
                break
            } catch {
                if Task.isCancelled || error is CancellationError { throw CancellationError() }
                let retryable = (error as? URLError).map { $0.code != .cancelled } ?? false
                guard retryable, attempt < VideoOfflineHTTPClient.maxAttempts else { throw error }
                AppLogger.shared.log("⚠️ [VideoOffline] Đứt khi tải file (lượt \(attempt)): \(error.localizedDescription) — tải tiếp")
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                attempt += 1
            }
        }

        let total = Self.fileSize(partURL)
        guard total > 0 else { throw VideoOfflineHTTPClient.ClientError.emptyBody }
        if let expected = lock.withLock({ self.expected }), total != expected {
            throw FileError.incomplete(total, expected)
        }
        let fileName = "video." + Self.fileExtension(mimeType: lock.withLock { self.mimeType }, url: url)
        let finalURL = directory.appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: partURL, to: finalURL)
        return Outcome(fileName: fileName, totalBytes: total)
    }

    // MARK: - Một lượt truyền

    private func transfer(url: URL, headers: [String: String], partURL: URL) async throws {
        let existing = Self.fileSize(partURL)
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if existing > 0 {
            request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range")
        }
        let fileHandle = try FileHandle(forWritingTo: partURL)
        lock.withLock {
            handle = fileHandle
            received = existing
            expected = nil
            responseError = nil
            responseChecked = false
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        let task = session.dataTask(with: request)
        defer {
            session.finishTasksAndInvalidate()
            lock.withLock { handle = nil }
            try? fileHandle.close()
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                lock.withLock { self.continuation = continuation }
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }
    }

    // MARK: - URLSessionDataDelegate
    //
    // Cố ý không cài `didReceive response:completionHandler:`: kiểu closure của nó đổi `@Sendable` theo SDK, lệch chữ ký
    // là delegate bị bỏ qua âm thầm. Phản hồi được kiểm ở gói dữ liệu đầu tiên (hoặc lúc kết thúc khi không có thân).

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let report: (Double, Int64)? = lock.withLock {
            if !responseChecked {
                responseChecked = true
                if let failure = acceptResponse(dataTask.response) {
                    responseError = failure
                    dataTask.cancel()
                    return nil
                }
            }
            guard responseError == nil else { return nil }
            do {
                try handle?.write(contentsOf: data)
            } catch {
                responseError = error
                dataTask.cancel()
                return nil
            }
            received += Int64(data.count)
            let now = CFAbsoluteTimeGetCurrent()
            guard now - lastProgressAt >= Self.progressInterval else { return nil }
            lastProgressAt = now
            let fraction = expected.map { $0 > 0 ? Double(received) / Double($0) : 0 } ?? 0
            return (fraction, received)
        }
        if let report {
            progress(report.0, report.1)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, failure): (CheckedContinuation<Void, Error>?, Error?) = lock.withLock {
            if !responseChecked, error == nil {
                responseChecked = true
                if let failure = acceptResponse(task.response) { responseError = failure }
            }
            let pending = self.continuation
            self.continuation = nil
            return (pending, responseError ?? error)
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else {
            continuation?.resume()
        }
    }

    /// Gọi trong `lock`. Áp phản hồi lên file bản dở (206 ⇒ nối tiếp; 2xx khác ⇒ máy chủ không hỗ trợ `Range`, ghi lại
    /// từ đầu); trả lỗi khi không nhận được.
    private func acceptResponse(_ response: URLResponse?) -> Error? {
        guard let http = response as? HTTPURLResponse else { return VideoOfflineHTTPClient.ClientError.invalidResponse }
        let mime = http.mimeType?.lowercased() ?? ""
        let length = http.expectedContentLength
        mimeType = mime
        switch http.statusCode {
        case 206:
            _ = try? handle?.seekToEnd()
            expected = length > 0 ? received + length : nil
        case 200...299:
            try? handle?.truncate(atOffset: 0)
            received = 0
            expected = length > 0 ? length : nil
        case 401, 403, 404, 410:
            return VideoOfflineHTTPClient.ClientError.linkRejected(http.statusCode)
        default:
            return VideoOfflineHTTPClient.ClientError.httpStatus(http.statusCode)
        }
        if mime.hasPrefix("text/") {
            return FileError.notMedia(mime)
        }
        return nil
    }

    // MARK: - Tiện ích

    private static func fileSize(_ url: URL) -> Int64 {
        ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// AVPlayer nhận dạng file trên máy theo đuôi ⇒ đuôi theo MIME, rồi theo URL, mặc định `mp4`.
    private static func fileExtension(mimeType: String?, url: URL) -> String {
        switch mimeType ?? "" {
        case "video/quicktime": return "mov"
        case "video/x-m4v": return "m4v"
        case "video/mp4": return "mp4"
        default: break
        }
        let ext = url.pathExtension.lowercased()
        return ["mp4", "m4v", "mov"].contains(ext) ? ext : "mp4"
    }
}
