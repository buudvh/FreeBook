import Foundation

/// Tải tài nguyên nhỏ cho bộ tải offline (playlist, khoá, đoạn HLS, phụ đề): header của tiện ích, `Range` cho byterange,
/// thử lại tối đa 3 lượt (chờ 1 s, 2 s) với lỗi mạng / 5xx / 408 / 429.
///
/// 401/403/404/410 ⇒ `linkRejected` ngay, không thử lại: thường là link có token đã hết hạn — `VideoEpisodeDownloadPipeline`
/// phân giải lại link một lần rồi tải tiếp bản dở.
final class VideoOfflineHTTPClient: @unchecked Sendable {
    enum ClientError: LocalizedError {
        case linkRejected(Int)
        case httpStatus(Int)
        case invalidResponse
        case emptyBody

        var errorDescription: String? {
            switch self {
            case .linkRejected(let code): return "Nguồn từ chối link tải (HTTP \(code)), có thể link đã hết hạn."
            case .httpStatus(let code): return "Máy chủ video trả lỗi HTTP \(code)."
            case .invalidResponse: return "Máy chủ video trả dữ liệu không hợp lệ."
            case .emptyBody: return "Máy chủ video trả dữ liệu rỗng."
            }
        }
    }

    static let maxAttempts = 3

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 2
        session = URLSession(configuration: configuration)
    }

    func invalidate() {
        session.invalidateAndCancel()
    }

    /// Byte của tài nguyên (đúng đoạn `range` nếu có). Máy chủ bỏ qua `Range` (trả 200 cả file) ⇒ tự cắt.
    func data(
        from url: URL,
        headers: [String: String],
        range: VideoHLSOfflinePlanner.ByteRange? = nil
    ) async throws -> Data {
        try await withRetry {
            let (data, _) = try await self.fetchOnce(url, headers: headers, range: range)
            return data
        }
    }

    /// Text của playlist/phụ đề kèm URL cuối sau chuyển hướng — URI tương đối trong playlist resolve theo URL này.
    func text(from url: URL, headers: [String: String]) async throws -> (text: String, finalURL: URL) {
        try await withRetry {
            let (data, response) = try await self.fetchOnce(url, headers: headers, range: nil)
            let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
            return (text, response.url ?? url)
        }
    }

    // MARK: - Nội bộ

    private func withRetry<T>(_ operation: () async throws -> T) async throws -> T {
        var attempt = 1
        while true {
            try Task.checkCancellation()
            do {
                return try await operation()
            } catch {
                if Task.isCancelled { throw CancellationError() }
                guard attempt < Self.maxAttempts, Self.isRetryable(error) else { throw error }
                try await Task.sleep(nanoseconds: UInt64(attempt) * 1_000_000_000)
                attempt += 1
            }
        }
    }

    private func fetchOnce(
        _ url: URL,
        headers: [String: String],
        range: VideoHLSOfflinePlanner.ByteRange?
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if let range {
            request.setValue("bytes=\(range.offset)-\(range.offset + range.length - 1)", forHTTPHeaderField: "Range")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch http.statusCode {
        case 206:
            guard !data.isEmpty else { throw ClientError.emptyBody }
            return (data, http)
        case 200...299:
            guard !data.isEmpty else { throw ClientError.emptyBody }
            guard let range, Int64(data.count) > range.length else { return (data, http) }
            let start = Int(range.offset)
            let end = start + Int(range.length)
            guard end <= data.count else { throw ClientError.invalidResponse }
            return (data.subdata(in: start..<end), http)
        case 401, 403, 404, 410:
            throw ClientError.linkRejected(http.statusCode)
        default:
            throw ClientError.httpStatus(http.statusCode)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        if let clientError = error as? ClientError {
            switch clientError {
            case .linkRejected: return false
            case .httpStatus(let code): return code >= 500 || code == 408 || code == 429
            case .invalidResponse, .emptyBody: return true
            }
        }
        if let urlError = error as? URLError {
            return urlError.code != .cancelled
        }
        return false
    }
}
