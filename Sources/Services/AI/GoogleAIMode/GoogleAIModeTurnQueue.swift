import Foundation

/// Hàng đợi tuần tự cho **mọi** lượt Chế độ AI của Google (1.3.609) — mọi truyện, cả chat lẫn quét tên riêng.
///
/// Chỉ có một WKWebView ẩn và mỗi lượt điều hướng trang ⇒ hai lượt song song giẫm lên nhau. Lượt quét tên riêng chờ đủ
/// `scanGap` kể từ lúc lượt Chế độ AI trước kết thúc (bất kể truyện nào) để Google không coi là gọi dồn dập (captcha);
/// chat không chờ khoảng nghỉ này nhưng vẫn xếp hàng sau lượt đang chạy. Task bị huỷ (người dùng bấm Dừng) khi đang
/// chờ ⇒ rời hàng ngay bằng `CancellationError`.
///
/// **Hạn chờ giới hạn** (1.3.612): Google báo hết hạn mức số câu trả lời AI ⇒ `noteRateLimited` đặt `blockedUntil`; tới
/// lúc đó mọi lượt (chat lẫn quét, mọi truyện) ném ngay `GoogleAIModeError.rateLimited` **trước** khi gửi — đang bị giới
/// hạn mà còn gửi thì chỉ kéo dài giới hạn. Hai lượt liên tiếp "Chế độ AI báo lỗi" (`generationFailed`, ở bất kỳ đâu)
/// cũng đặt hạn chờ này — người dùng gặp đúng lỗi đó khi Google giới hạn mà trang không hiện câu giới hạn.
actor GoogleAIModeTurnQueue {
    static let shared = GoogleAIModeTurnQueue()

    /// Khoảng nghỉ tối thiểu trước mỗi lượt quét tên riêng (người dùng chọn 5 s).
    static let scanGap: TimeInterval = 5

    /// Máy nóng ⇒ giãn nhịp quét (1.3.963): mỗi lượt là một lần nạp trang Google đầy đủ (tải + biên dịch JS, dựng trang)
    /// trong tiến trình web — % CPU của app (`DeviceThermalMonitor`) không tính phần này. Quét cả truyện là hàng chục lượt
    /// liền nhau; nghỉ lâu hơn khi iOS báo Ấm / Nóng / Rất nóng để máy kịp hạ nhiệt. Chat không bị giãn (người dùng đang chờ).
    /// Log build 1289 (iPhone 11, TTS Google chỉ bận ~5%): quét nhịp 5 s (~9 s/lượt, lượt ~4 s) ⇒ Mát → Ấm sau ~2 phút,
    /// → Nóng sau ~5 phút, ngừng quét thì 2–4 phút sau hạ về Ấm — nên giãn từ mức Ấm.
    static func thermalScanGap(_ state: ProcessInfo.ThermalState) -> TimeInterval {
        switch state {
        case .fair: return 10
        case .serious: return 20
        case .critical: return 60
        default: return Self.scanGap
        }
    }

    private var isBusy = false
    private var waiters: [(id: UUID, continuation: CheckedContinuation<Void, Error>)] = []
    private var lastTurnEndedAt: Date?
    private var blockedUntil: Date?
    private var consecutiveGenerationFailures = 0
    /// Mức nhiệt lúc ghi dòng "giãn nhịp quét" gần nhất.
    private var lastLoggedThermal: ProcessInfo.ThermalState?

    /// Hạn chờ khi hai lượt liên tiếp báo lỗi (giây).
    private static let failureCooldown: TimeInterval = 60

    private init() {}

    /// Google vừa báo giới hạn (hoặc vòng quét đang chờ): chặn mọi lượt tới `until` — giữ mốc xa hơn nếu đã có.
    func noteRateLimited(until: Date) {
        if let current = blockedUntil, current >= until { return }
        blockedUntil = until
    }

    func noteRateLimited(for seconds: TimeInterval) {
        noteRateLimited(until: Date().addingTimeInterval(seconds))
    }

    /// Bỏ hạn chờ toàn cục (1.3.614): vừa tráo sang **tài khoản Google khác** thì hạn chờ của tài khoản cũ không còn
    /// nghĩa — lượt gửi lại phải đi ngay, không bị chặn 60 s của tài khoản trước.
    func clearRateLimitBlock() {
        blockedUntil = nil
    }

    /// Chạy `body` khi tới lượt; luôn nhả hàng ở mọi lối ra.
    func run<Value: Sendable>(isScan: Bool, _ body: @Sendable () async throws -> Value) async throws -> Value {
        try throwIfBlocked()
        try await acquire()
        do {
            try throwIfBlocked()
            if isScan, let ended = lastTurnEndedAt {
                let thermal = ProcessInfo.processInfo.thermalState
                let gap = Self.thermalScanGap(thermal)
                let remaining = gap - Date().timeIntervalSince(ended)
                // Chỉ ghi khi mức nhiệt đổi — quét cả truyện ở mức Ấm là hàng chục lượt.
                if thermal != lastLoggedThermal {
                    lastLoggedThermal = thermal
                    if gap > Self.scanGap {
                        let label = thermal == .critical ? "Rất nóng" : thermal == .serious ? "Nóng" : "Ấm"
                        AppLogger.shared.log("🌡️ [AIMode] Máy \(label) — giãn nhịp quét tên riêng: nghỉ \(Int(gap)) s giữa hai lượt")
                    }
                }
                if remaining > 0 {
                    try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
                }
            }
            try Task.checkCancellation()
            let value = try await body()
            consecutiveGenerationFailures = 0
            release()
            return value
        } catch {
            if let failure = error as? GoogleAIModeError, failure == .generationFailed {
                consecutiveGenerationFailures += 1
                if consecutiveGenerationFailures >= 2 {
                    AppLogger.shared.log("❌ 🤖 [AIMode] \(consecutiveGenerationFailures) lượt liên tiếp báo lỗi — coi như bị Google giới hạn, chặn mọi lượt \(Int(Self.failureCooldown)) s")
                    noteRateLimited(for: Self.failureCooldown)
                }
            }
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
        throw GoogleAIModeError.rateLimited(retryAfter: Int(remaining.rounded(.up)))
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
