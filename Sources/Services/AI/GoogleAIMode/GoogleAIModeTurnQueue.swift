import Foundation

/// Hàng đợi tuần tự cho **mọi** lượt Chế độ AI của Google (1.3.609) — mọi truyện, cả chat lẫn quét tên riêng.
///
/// Chỉ có một WKWebView ẩn và mỗi lượt điều hướng trang ⇒ hai lượt song song giẫm lên nhau. Lượt quét tên riêng chờ đủ
/// `scanGap` kể từ lúc lượt Chế độ AI trước kết thúc (bất kể truyện nào) để Google không coi là gọi dồn dập (captcha);
/// chat không chờ khoảng nghỉ này nhưng vẫn xếp hàng sau lượt đang chạy. Task bị huỷ (người dùng bấm Dừng) khi đang
/// chờ ⇒ rời hàng ngay bằng `CancellationError`.
actor GoogleAIModeTurnQueue {
    static let shared = GoogleAIModeTurnQueue()

    /// Khoảng nghỉ tối thiểu trước mỗi lượt quét tên riêng (người dùng chọn 5 s).
    static let scanGap: TimeInterval = 5

    private var isBusy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastTurnEndedAt: Date?

    private init() {}

    /// Chạy `body` khi tới lượt; luôn nhả hàng ở mọi lối ra.
    func run<Value: Sendable>(isScan: Bool, _ body: @Sendable () async throws -> Value) async throws -> Value {
        try await acquire()
        do {
            if isScan, let ended = lastTurnEndedAt {
                let remaining = Self.scanGap - Date().timeIntervalSince(ended)
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
