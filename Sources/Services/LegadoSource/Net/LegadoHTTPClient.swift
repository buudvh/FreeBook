import Foundation
import Network

/// HTTP client của **một** phiên engine: `URLSession` ephemeral riêng, không kho cookie hệ thống (cookie do
/// `LegadoCookieJar` quản), không cache, **không tự theo chuyển hướng** — `LegadoEngineSession` tự đi từng chặng để
/// lưu `Set-Cookie` ở mọi chặng và để `java.get/post/head` thấy được phản hồi 3xx (spec §4.2, §4.7).
///
/// Gọi đồng bộ trên thread engine; chờ theo lát ngắn để huỷ có hiệu lực ngay (`LegadoEngineCancellation`).
final class LegadoHTTPClient {
    /// UA mặc định khi nguồn không khai: Chrome **máy tính** Windows (spec §3.10 mục 6). Dùng cho request luồng chính (cả
    /// trang tải bằng WebView — `LegadoURLBuilder` luôn đặt UA này trước header nguồn) và `java.ajax`/`get`/`post`. UA di
    /// động làm nhiều trang chuyển sang bản `m.`/`wap.` mà rule không khớp (黑岩, 若初, 若夏, 塔读, 红袖).
    static let defaultUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
    /// UA của WebView Android (`java.getWebViewUA()`, §6.4.4) — giữ nguyên cho `java.webView`, trình duyệt của nguồn.
    static let webViewUserAgent = "Mozilla/5.0 (Linux; Android 13; Pixel 7 Build/TQ3A.230901.001; wv) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/124.0.0.0 Mobile Safari/537.36"

    struct Hop {
        var data: Data
        var response: HTTPURLResponse
    }

    private final class ResultBox: @unchecked Sendable {
        var data: Data?
        var response: URLResponse?
        var error: Error?
    }

    private let session: URLSession
    private let cancellation: LegadoEngineCancellation

    /// `proxyConfigurations`: proxy nội bộ DNS mã hoá khi nguồn bật cờ (`EncryptedDNSSessionRouter`), rỗng = đi thẳng.
    init(cancellation: LegadoEngineCancellation, proxyConfigurations: [ProxyConfiguration] = []) {
        self.cancellation = cancellation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = 4
        if !proxyConfigurations.isEmpty {
            configuration.proxyConfigurations = proxyConfigurations
        }
        session = URLSession(configuration: configuration, delegate: LegadoHTTPSessionDelegate(), delegateQueue: nil)
    }

    /// Gọi khi phiên kết thúc: `URLSession` giữ delegate mạnh cho tới khi bị vô hiệu.
    func invalidate() {
        session.finishTasksAndInvalidate()
    }

    /// Một chặng (không theo chuyển hướng). Lỗi mạng ném `URLError`; bị huỷ ném `CancellationError`.
    func send(_ request: URLRequest) throws -> Hop {
        try cancellation.check()
        let semaphore = DispatchSemaphore(value: 0)
        let box = ResultBox()
        let task = session.dataTask(with: request) { data, response, error in
            box.data = data
            box.response = response
            box.error = error
            semaphore.signal()
        }
        let handlerId = cancellation.register { task.cancel() }
        defer { cancellation.unregister(handlerId) }
        task.resume()

        let limit = max(5, request.timeoutInterval) * 2 + 5
        let finished: Bool
        do {
            finished = try cancellation.wait(semaphore, timeout: limit)
        } catch {
            task.cancel()
            throw error
        }
        guard finished else {
            task.cancel()
            throw URLError(.timedOut)
        }
        try cancellation.check()
        if let error = box.error { throw error }
        guard let response = box.response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return Hop(data: box.data ?? Data(), response: response)
    }

    /// Lỗi mạng tạm thời đáng thử lại (§4.3).
    static func isTransient(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet,
             .dnsLookupFailed, .cannotFindHost, .secureConnectionFailed:
            return true
        default:
            return false
        }
    }
}
