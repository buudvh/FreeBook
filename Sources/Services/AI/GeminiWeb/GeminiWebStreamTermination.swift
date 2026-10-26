import Foundation

/// Gắn `onTermination` cho stream của `GeminiWebSessionController.fetchStream` **ngay lúc tạo stream** và nhớ stream đã
/// kết thúc chưa (1.3.602).
///
/// Trước đây handler chỉ được gắn bên trong `Task { @MainActor … }` chạy trễ: consumer rời stream trước khi Task đó kịp
/// chạy (vd lượt quét tên riêng bị huỷ vì app vào nền đúng lúc đang chuyển sang MainActor) thì không có handler nào huỷ
/// `fetch`, rồi Task vẫn đăng ký stream và chạy `fetch` trong trang — fetch mồ côi chạy vào cùng cuộc chat với lượt gửi
/// lại, watchdog của nó còn ghi một dòng timeout giả. Nay Task kiểm `isTerminated` trước khi chạy fetch.
final class GeminiWebStreamTermination: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false

    /// `onTerminate` chạy mỗi khi stream kết thúc vì bất kỳ lý do gì (consumer huỷ, `finish`, `finish(throwing:)`).
    init(_ continuation: AsyncThrowingStream<String, Error>.Continuation, onTerminate: @escaping @Sendable () -> Void) {
        continuation.onTermination = { [self] _ in
            self.lock.lock()
            self.terminated = true
            self.lock.unlock()
            onTerminate()
        }
    }

    var isTerminated: Bool {
        lock.lock()
        defer { lock.unlock() }
        return terminated
    }
}
