import Foundation

/// Tải **một** file qua `URLSessionDownloadTask` và bắc cầu sang async/await.
///
/// Vì sao không dùng `URLSession.bytes(for:)`: nó là `AsyncSequence` của **từng byte**, nên 274 MB
/// thành 274 triệu lần `await next()`. Overhead đó lớn hơn cả thời gian tải. `URLSessionDownloadTask`
/// ghi thẳng xuống file ở tầng hệ thống và báo tiến độ qua delegate.
///
/// Delegate cũng là cách duy nhất lấy được tiến độ **theo byte**. Với một bộ gồm một file 104 MB và
/// một file 500 byte thì tiến độ "đã xong file thứ mấy" là vô nghĩa.
final class VieNeuFileDownload: NSObject, URLSessionDownloadDelegate {
    private var continuation: CheckedContinuation<URL, Error>?
    private let onProgress: @Sendable (Int64, Int64) -> Void
    private var session: URLSession?
    private var didResume = false
    private let lock = NSLock()

    /// - Parameter onProgress: `(đã tải, tổng dự kiến)`. `tổng` là `-1` khi máy chủ không khai
    ///   `Content-Length`.
    init(onProgress: @escaping @Sendable (Int64, Int64) -> Void) {
        self.onProgress = onProgress
        super.init()
    }

    /// Tải `request` và trả về file tạm. Caller chịu trách nhiệm di chuyển file đó đi.
    func run(request: URLRequest) async throws -> (url: URL, response: HTTPURLResponse) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        // 274 MB trên 4G có thể mất rất lâu; mặc định 7 ngày của `timeoutIntervalForResource` là quá
        // rộng nhưng chặn ở 2 giờ thì một file không bao giờ bị treo vô hạn.
        configuration.timeoutIntervalForResource = 7_200
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session

        let fileURL: URL = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                self.continuation = continuation
                lock.unlock()
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }

        guard let http = lastResponse else {
            session.finishTasksAndInvalidate()
            throw TTSError.internalError("Không nhận được phản hồi HTTP")
        }
        session.finishTasksAndInvalidate()
        return (fileURL, http)
    }

    private var lastResponse: HTTPURLResponse?

    // MARK: - URLSessionDownloadDelegate

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(totalBytesWritten, totalBytesExpectedToWrite)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        lastResponse = downloadTask.response as? HTTPURLResponse

        // File tạm của hệ thống bị xoá ngay khi delegate trả về, nên phải chuyển đi **trong** hàm này.
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("vieneu-\(UUID().uuidString).part")
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            resume(.success(destination))
        } catch {
            resume(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        resume(.failure(error))
    }

    /// Continuation chỉ được resume **một** lần: `didFinishDownloadingTo` và `didCompleteWithError`
    /// đều có thể được gọi cho cùng một task.
    private func resume(_ result: Result<URL, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        switch result {
        case .success(let url): pending.resume(returning: url)
        case .failure(let error): pending.resume(throwing: error)
        }
    }
}
