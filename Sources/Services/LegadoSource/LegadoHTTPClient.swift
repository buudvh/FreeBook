import Foundation

/// Client HTTP của phân hệ nguồn Legado.
///
/// Repo không có tầng mạng dùng chung (mỗi phân hệ tự gọi `URLSession`), nên đây là client riêng.
/// Hai điểm bắt buộc mà `URLSession` mặc định không làm đúng cho nguồn truyện Trung Quốc:
/// giải mã theo bảng mã nguồn khai (GBK/Big5) và giữ cookie theo phiên của từng nguồn.
public final class LegadoHTTPClient: @unchecked Sendable {
    public static let shared = LegadoHTTPClient()

    private let session: URLSession
    private static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 "
        + "(KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.httpCookieAcceptPolicy = .always
        configuration.httpShouldSetCookies = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public enum ClientError: LocalizedError {
        case invalidURL(String)
        case httpStatus(Int, String)
        case emptyBody(String)

        public var errorDescription: String? {
            switch self {
            case .invalidURL(let url):
                return "URL không hợp lệ: \(url)"
            case .httpStatus(let code, let url):
                return "Máy chủ trả về HTTP \(code) cho \(url)"
            case .emptyBody(let url):
                return "Phản hồi rỗng từ \(url)"
            }
        }
    }

    /// Gửi yêu cầu, tự thử lại theo `spec.retry` (Legado retry **bên trong** tầng này, tầng trên
    /// không được bọc thêm vòng retry — cùng nguyên tắc với `RemoteTTSSynthesisCoordinator`).
    public func send(_ spec: LegadoRequestSpec) async throws -> LegadoHTTPResponse {
        var lastError: Error = ClientError.emptyBody(spec.url)
        let attempts = max(1, min(spec.retry + 1, 3))

        for attempt in 1...attempts {
            do {
                return try await perform(spec)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
                if attempt < attempts {
                    AppLogger.shared.log("🔁 [LegadoHTTP] Thử lại \(attempt)/\(attempts - 1) cho \(spec.url): \(error.localizedDescription)")
                    try? await Task.sleep(nanoseconds: 800_000_000)
                }
            }
        }
        throw lastError
    }

    private func perform(_ spec: LegadoRequestSpec) async throws -> LegadoHTTPResponse {
        guard let url = LegadoUrlBuilder.makeURL(spec.url) else {
            throw ClientError.invalidURL(spec.url)
        }
        var request = URLRequest(url: url)
        request.httpMethod = spec.method.uppercased()
        request.httpBody = spec.body

        var headers = spec.headers
        if !headers.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            headers["User-Agent"] = Self.defaultUserAgent
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        try Task.checkCancellation()
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()

        let httpResponse = response as? HTTPURLResponse
        let statusCode = httpResponse?.statusCode ?? 0
        var headerMap: [String: String] = [:]
        if let fields = httpResponse?.allHeaderFields {
            for (key, value) in fields {
                if let name = key as? String, let text = value as? String {
                    headerMap[name] = text
                }
            }
        }

        guard (200..<400).contains(statusCode) else {
            throw ClientError.httpStatus(statusCode, spec.url)
        }

        let body = LegadoTextEncoding.decode(data, declaredCharset: spec.charset)
        return LegadoHTTPResponse(
            statusCode: statusCode,
            body: body,
            rawData: data,
            headers: headerMap,
            finalUrl: httpResponse?.url?.absoluteString ?? spec.url
        )
    }

    /// Bản đồng bộ cho bridge JS (`java.ajax`, `java.get`, `java.post`).
    ///
    /// Rhino của Legado là engine đồng bộ và `java.ajax` chặn luồng; JavaScriptCore cũng vậy, nên phải
    /// chặn. Dùng `DispatchSemaphore` với **thời gian chờ có giới hạn**, theo đúng khuôn
    /// `_nativeSyncFetch` của `JSExecutor` đã chạy ổn định. Luật cấm semaphore của repo áp cho việc
    /// chờ `WKWebView` (gây deadlock main thread), không áp cho `URLSession` chạy ngoài main.
    public func sendBlocking(_ spec: LegadoRequestSpec, timeout: TimeInterval = 30) -> LegadoHTTPResponse? {
        guard let url = LegadoUrlBuilder.makeURL(spec.url) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = spec.method.uppercased()
        request.httpBody = spec.body

        var headers = spec.headers
        if !headers.keys.contains(where: { $0.lowercased() == "user-agent" }) {
            headers["User-Agent"] = Self.defaultUserAgent
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        let semaphore = DispatchSemaphore(value: 0)
        var result: LegadoHTTPResponse?

        let task = session.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data else { return }
            let httpResponse = response as? HTTPURLResponse
            var headerMap: [String: String] = [:]
            if let fields = httpResponse?.allHeaderFields {
                for (key, value) in fields {
                    if let name = key as? String, let text = value as? String {
                        headerMap[name] = text
                    }
                }
            }
            result = LegadoHTTPResponse(
                statusCode: httpResponse?.statusCode ?? 0,
                body: LegadoTextEncoding.decode(data, declaredCharset: spec.charset),
                rawData: data,
                headers: headerMap,
                finalUrl: httpResponse?.url?.absoluteString ?? spec.url
            )
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            // Chờ ngắn thêm để callback không ghi vào `result` sau khi hàm đã trả về.
            _ = semaphore.wait(timeout: .now() + 1.0)
            AppLogger.shared.log("⏱️ [LegadoHTTP] Hết thời gian chờ đồng bộ: \(spec.url)")
            return nil
        }
        return result
    }
}
