import Foundation
import UIKit

/// Theo dõi app đang ở trước hay ở nền cho lượt quét tên riêng Gemini Web (1.3.602).
///
/// Log máy thật 21–26/10: mọi lượt quét lỗi "không phản hồi kịp thời gian chờ" (`StreamGenerate lỗi sau ~150 000 ms,
/// chunk=0`) đều rơi lúc app ở nền — TTS giữ tiến trình app sống nhưng iOS tạm dừng tiến trình web của WKWebView ẩn,
/// `fetch()` trong trang đứng im tới hết idle timeout. `GeminiWebClient+NameScan` dùng cổng này để tạm dừng lượt quét
/// khi app ở nền và gửi lại khi app mở lại.
///
/// - **Chỉ `didEnterBackground`** tính là vào nền (tăng "kỷ nguyên nền" `epoch`). `willResignActive` (Control Center,
///   banner cuộc gọi, kéo thông báo) không tính: tiến trình web vẫn chạy, không được huỷ lượt.
/// - `willEnterForeground` / `didBecomeActive` đánh dấu đã về trước và đánh thức các lượt đang chờ.
/// - Trạng thái nằm dưới khoá ⇒ đọc được từ actor `GeminiWebClient` lẫn MainActor. Hàm chờ phản hồi huỷ: task bị huỷ
///   (người dùng bấm Dừng) ⇒ ném `CancellationError` ngay.
final class GeminiWebForegroundGate: @unchecked Sendable {
    static let shared = GeminiWebForegroundGate()

    private typealias Waiter = CheckedContinuation<Int, Error>

    private let lock = NSLock()
    private var isInstalled = false
    private var inBackground = false
    /// Tăng mỗi lần app vào nền — lượt gửi ghi lại lúc bắt đầu để biết app có vào nền trong lúc lượt chạy không.
    private var epoch = 0
    private var foregroundWaiters: [UUID: Waiter] = [:]
    private var backgroundWaiters: [UUID: Waiter] = [:]

    private init() {
        // Kích hoạt sớm để nhãn log đúng cả khi chưa có lượt quét nào; lượt quét vẫn tự `await installIfNeeded()`.
        Task { @MainActor [self] in self.installIfNeeded() }
    }

    // MARK: - Trạng thái

    var isInBackground: Bool {
        lock.lock(); defer { lock.unlock() }
        return inBackground
    }

    /// App đã vào nền (ít nhất một lần) kể từ lúc ghi `recorded` chưa.
    func hasEnteredBackground(since recorded: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return epoch != recorded
    }

    /// Nhãn trạng thái app cho dòng log ❌ — ảnh chụp dưới khoá, gọi được từ mọi luồng. Cổng chưa kịp kích hoạt (lần đầu
    /// chạm `shared` có thể chính là dòng log này, việc kích hoạt chạy sau trên MainActor) ⇒ không đoán.
    var appStateLabel: String {
        lock.lock()
        defer { lock.unlock() }
        return isInstalled ? Self.label(inBackground: inBackground) : "(chưa rõ app ở nền hay đang mở)"
    }

    /// Cùng nhãn nhưng đọc thẳng `applicationState` — cho code đã ở MainActor, đúng cả khi cổng chưa kích hoạt.
    @MainActor
    static var currentAppStateLabel: String {
        label(inBackground: UIApplication.shared.applicationState == .background)
    }

    private static func label(inBackground: Bool) -> String {
        inBackground ? "(app ở nền)" : "(app đang mở)"
    }

    // MARK: - Kích hoạt

    /// Đăng ký theo dõi (một lần) rồi đọc trạng thái hiện tại — cùng một nhịp MainActor nên không lọt lần chuyển trạng
    /// thái nào (notification của `UIApplication` phát trên main thread).
    @MainActor
    func installIfNeeded() {
        lock.lock()
        let alreadyInstalled = isInstalled
        isInstalled = true
        lock.unlock()
        guard !alreadyInstalled else { return }

        let center = NotificationCenter.default
        _ = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil) { [weak self] _ in
            self?.markBackground()
        }
        for name in [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification] {
            _ = center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                self?.markForeground()
            }
        }
        if UIApplication.shared.applicationState == .background {
            markBackground()
        }
    }

    private func markBackground() {
        lock.lock()
        inBackground = true
        epoch += 1
        let current = epoch
        let waiters = backgroundWaiters
        backgroundWaiters.removeAll()
        lock.unlock()
        waiters.values.forEach { $0.resume(returning: current) }
    }

    private func markForeground() {
        lock.lock()
        inBackground = false
        let current = epoch
        let waiters = foregroundWaiters
        foregroundWaiters.removeAll()
        lock.unlock()
        waiters.values.forEach { $0.resume(returning: current) }
    }

    // MARK: - Chờ

    /// Chờ tới khi app ở trước (trả ngay nếu đang ở trước). Trả `epoch` lúc đó để lượt gửi đối chiếu về sau.
    func waitUntilForeground() async throws -> Int {
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Waiter) in
                self.lock.lock()
                if Task.isCancelled {
                    self.lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if !self.inBackground {
                    let current = self.epoch
                    self.lock.unlock()
                    continuation.resume(returning: current)
                } else {
                    self.foregroundWaiters[id] = continuation
                    self.lock.unlock()
                }
            }
        } onCancel: {
            self.lock.lock()
            let waiter = self.foregroundWaiters.removeValue(forKey: id)
            self.lock.unlock()
            waiter?.resume(throwing: CancellationError())
        }
    }

    /// Chờ tới khi app vào nền **sau** lúc ghi `recorded` (trả ngay nếu đã vào nền kể từ đó). Bị huỷ (lượt gửi xong
    /// trước, hoặc người dùng bấm Dừng) ⇒ ném `CancellationError`.
    func waitForBackground(after recorded: Int) async throws {
        let id = UUID()
        _ = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: Waiter) in
                self.lock.lock()
                if Task.isCancelled {
                    self.lock.unlock()
                    continuation.resume(throwing: CancellationError())
                } else if self.epoch != recorded {
                    let current = self.epoch
                    self.lock.unlock()
                    continuation.resume(returning: current)
                } else {
                    self.backgroundWaiters[id] = continuation
                    self.lock.unlock()
                }
            }
        } onCancel: {
            self.lock.lock()
            let waiter = self.backgroundWaiters.removeValue(forKey: id)
            self.lock.unlock()
            waiter?.resume(throwing: CancellationError())
        }
    }
}
