import Foundation

/// Cầu nối engine nguồn Legado → UI (spec §10.8, §11.5): engine **phát** yêu cầu (trình duyệt hiện cho người dùng, mã
/// xác minh, làm mới khám phá…) qua `stream`; một presenter duy nhất ở tầng UI subscribe và **trả kết quả** bằng
/// `completeBrowser` / `completeVerification`. Services không có UI (không `import SwiftUI`, không gọi toast trực tiếp).
///
/// Cách presenter dùng (U2):
/// ```swift
/// let center = LegadoPresentationEventCenter.shared
/// center.attachPresenter()                       // chỉ khi đã gắn mới có yêu cầu UI được phát
/// for await event in center.stream {
///     switch event {
///     case .browser(let request): /* sheet trình duyệt; xong ⇒ center.completeBrowser(id: request.id, result: …) */
///     case .verificationCode(let request): /* ảnh + ô nhập ⇒ center.completeVerification(id:code:) (nil = huỷ) */
///     case .dismiss(let id): /* đóng sheet của id nếu còn mở */
///     default: break
///     }
/// }
/// ```
///
/// - Tối đa **một** trình duyệt/hộp mã hiện cùng lúc toàn app; yêu cầu sau xếp hàng (center tự phát yêu cầu kế khi
///   yêu cầu trước kết thúc).
/// - Chưa có presenter, hoặc phiên không có người dùng (`LegadoEngineSession.allowsUserInteraction == false`): yêu cầu
///   UI **không** được phát, engine trả ngay kết quả "không có người dùng".
/// - Thread engine chờ ngoài main, có hạn giờ; hết giờ hoặc phiên bị huỷ ⇒ center phát `.dismiss(requestId:)`.
final class LegadoPresentationEventCenter: @unchecked Sendable {
    static let shared = LegadoPresentationEventCenter()

    let stream: AsyncStream<LegadoPresentationEvent>
    private let continuation: AsyncStream<LegadoPresentationEvent>.Continuation

    private let lock = NSLock()
    private var presenterCount = 0
    private var active: LegadoPresentationTicket?
    private var queue: [LegadoPresentationTicket] = []
    private var pendingExploreRefresh: Set<String> = []

    private init() {
        let (stream, continuation) = AsyncStream<LegadoPresentationEvent>.makeStream(bufferingPolicy: .bufferingNewest(64))
        self.stream = stream
        self.continuation = continuation
    }

    // MARK: - Presenter

    /// Presenter gọi khi bắt đầu subscribe (và `detachPresenter()` khi thôi) để engine biết có UI trình bày được.
    func attachPresenter() {
        lock.lock()
        presenterCount += 1
        lock.unlock()
    }

    func detachPresenter() {
        lock.lock()
        presenterCount = max(0, presenterCount - 1)
        let orphaned = presenterCount == 0 ? ([active].compactMap { $0 } + queue) : []
        lock.unlock()
        for ticket in orphaned {
            cancel(ticket.id)
        }
    }

    var hasPresenter: Bool {
        lock.lock()
        defer { lock.unlock() }
        return presenterCount > 0
    }

    /// Kết quả cho `.browser(request)`. Gọi từ luồng bất kỳ (thường main); gọi lần hai bị bỏ qua.
    func completeBrowser(id: UUID, result: LegadoBrowserResult) {
        finish(id, browser: result, code: nil, notifyDismiss: false)
    }

    /// Kết quả cho `.verificationCode(request)`; `nil` = người dùng huỷ (JS nhận `""`).
    func completeVerification(id: UUID, code: String?) {
        finish(id, browser: nil, code: code ?? "", notifyDismiss: false)
    }

    // MARK: - Engine

    /// Gửi sự kiện thông báo (không cần kết quả).
    func send(_ event: LegadoPresentationEvent) {
        continuation.yield(event)
    }

    /// Xếp hàng một yêu cầu UI; phát ngay nếu không có yêu cầu nào đang hiện.
    func enqueue(_ ticket: LegadoPresentationTicket) {
        lock.lock()
        let showNow = active == nil
        if showNow {
            active = ticket
        } else {
            queue.append(ticket)
        }
        lock.unlock()
        if showNow { continuation.yield(ticket.event) }
    }

    /// Huỷ phía engine (hết giờ, phiên bị huỷ): kết thúc yêu cầu không kết quả, báo presenter đóng nếu đang hiện.
    func cancel(_ id: UUID) {
        finish(id, browser: nil, code: nil, notifyDismiss: true)
    }

    /// `java.refreshExplore()`: gom các lần gọi trong 300 ms của cùng nguồn thành một sự kiện.
    func scheduleExploreRefresh(sourceKey: String) {
        lock.lock()
        let inserted = pendingExploreRefresh.insert(sourceKey).inserted
        lock.unlock()
        guard inserted else { return }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            self.pendingExploreRefresh.remove(sourceKey)
            self.lock.unlock()
            self.continuation.yield(.refreshExplore(sourceKey: sourceKey))
        }
    }

    // MARK: - Nội bộ

    private func finish(_ id: UUID, browser: LegadoBrowserResult?, code: String?, notifyDismiss: Bool) {
        lock.lock()
        var ticket: LegadoPresentationTicket?
        var next: LegadoPresentationTicket?
        var wasActive = false
        if let current = active, current.id == id {
            ticket = current
            wasActive = true
            next = queue.isEmpty ? nil : queue.removeFirst()
            active = next
        } else if let index = queue.firstIndex(where: { $0.id == id }) {
            ticket = queue.remove(at: index)
        }
        lock.unlock()
        guard let ticket else { return }
        let finishedNow = ticket.finish(browser: browser, code: code)
        if finishedNow, notifyDismiss, wasActive {
            continuation.yield(.dismiss(requestId: id))
        }
        if let next {
            continuation.yield(next.event)
        }
        if finishedNow {
            ticket.onFinish?(ticket)
        }
    }
}
