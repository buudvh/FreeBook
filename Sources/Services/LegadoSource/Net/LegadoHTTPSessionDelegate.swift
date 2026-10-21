import Foundation

/// Delegate của `LegadoHTTPClient`: **chặn** mọi chuyển hướng tự động để phản hồi 3xx về tay engine
/// (engine tự đi tiếp khi request cần theo chuyển hướng, và lưu `Set-Cookie` của từng chặng).
final class LegadoHTTPSessionDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
