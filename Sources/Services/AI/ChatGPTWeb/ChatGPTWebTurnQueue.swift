import Foundation

/// Hàng đợi tuần tự cho **mọi** lượt ChatGPT Web (1.3.971) — mọi truyện, cả chat lẫn quét tên riêng: chỉ có một
/// WKWebView ẩn, hai lượt song song giẫm lên nhau.
///
/// - Lượt quét tên riêng chờ đủ khoảng nghỉ kể từ lúc lượt ChatGPT Web trước kết thúc (bất kể truyện nào); máy Ấm / Nóng /
///   Rất nóng thì giãn theo `GoogleAIModeTurnQueue.thermalScanGap`. Chat không chờ khoảng nghỉ nhưng vẫn xếp hàng.
/// - Task bị huỷ khi đang chờ ⇒ rời hàng ngay bằng `CancellationError`.
/// - **Hạn chờ giới hạn**: ChatGPT báo hết lượt hỏi ẩn danh ⇒ `noteRateLimited` đặt `blockedUntil`; tới lúc đó mọi lượt ném
///   ngay `ChatGPTWebError.rateLimited` **trước** khi gửi. App không tìm cách lách giới hạn (không xoá cookie /
///   `localStorage`, không đổi danh tính).
actor ChatGPTWebTurnQueue {
    static let shared = ChatGPTWebTurnQueue()

    private var isBusy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastTurnEndedAt: Date?
    private var blockedUntil: Date?

    private init() {}

    func noteRateLimited(for seconds: TimeInterval) {
        let until = Date().addingTimeInterval(seconds)
        if let current = blockedUntil, current >= until { return }
        blockedUntil = until
    }

    /// Chạy `body` khi tới lượt; luôn nhả hàng ở mọi lối ra.
    func run<Value: Sendable>(isScan: Bool, _ body: @Sendable () async throws -> Value) async throws -> Value {
        try throwIfBlocked()
        try await acquire()
        do {
            try throwIfBlocked()
            if isScan, let ended = lastTurnEndedAt {
                let gap = GoogleAIModeTurnQueue.thermalScanGap(ProcessInfo.processInfo.thermalState)
                let remaining = gap - Date().timeIntervalSince(ended)
                if remaining > 0 {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
            try Task.checkCancellation()
            let value = try await body()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    /// Còn trong hạn chờ giới hạn ⇒ ném `rateLimited` với số giây còn lại, không gửi gì.
    private func throwIfBlocked() throws {
        guard let until = blockedUntil else { return }
        let remaining = until.timeIntervalSinceNow
        guard remaining > 0 else {
            blockedUntil = nil
            return
        }
        throw ChatGPTWebError.rateLimited(retryAfter: Int(remaining.rounded(.up)))
    }

    private func acquire() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if !isBusy {
                    isBusy = true
                    continuation.resume()
                } else {
                    waiters.append((id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(id: id) }
        }
    }

    /// Giao lượt cho người chờ đầu tiên (vẫn giữ `isBusy`), hoặc mở hàng.
    private func release() {
        lastTurnEndedAt = Date()
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().continuation.resume()
        }
    }

    /// Người chờ bị huỷ trước khi tới lượt. Đã tới lượt rồi thì không còn trong hàng — `run` tự thấy huỷ và nhả hàng.
    private func cancelWaiter(id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }
}
