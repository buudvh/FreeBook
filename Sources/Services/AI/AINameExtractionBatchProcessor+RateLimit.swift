import Foundation

/// Quét tên riêng khi Chế độ AI của Google bị giới hạn số câu trả lời AI (1.3.612, xoay tài khoản từ 1.3.616).
///
/// Bằng chứng (người dùng, 2026-10-26): quét được một lúc thì app báo "Chế độ AI của Google báo lỗi…", mở trang thì Google
/// ghi "Bạn hiện đã đạt đến giới hạn về số lượng yêu cầu đối với câu trả lời của AI. Hãy thử lại sau giây lát". Bản
/// 1.3.609 khi đó vẫn gửi lại ngay rồi quét tiếp mỗi 5 s ⇒ càng gửi càng bị giới hạn lâu. Ở đây, lỗi được
/// `GoogleAccountRotation.treatsAsRateLimit` coi là bị giới hạn thì:
/// - còn **tài khoản Google khác** trong cùng provider (Chế độ AI giữ nhiều tài khoản) ⇒ tráo phiên, gửi lại đúng lượt đó
///   bằng tài khoản mới (1.3.616);
/// - có profile Gemini Web ⇒ chuyển sang đó (người dùng chọn ở 1.3.612);
/// - không có gì để chuyển ⇒ chờ theo nấc 1 → 2 → 4 → 8 phút (đặt luôn hạn chờ của `GoogleAIModeTurnQueue` để chat cũng
///   không gửi), báo tiến độ mỗi 15 s để dải tiến độ và tiêu đề tác vụ đếm ngược, chờ xong gửi lại đúng lượt đó; hết nấc
///   ⇒ ném `rateLimitExhausted` (lỗi dừng quét — tên và điểm tiếp nối giữ như mọi lỗi dừng).
/// Không có cách "lách" nào khác (đổi IP, giả trình duyệt): đổi tài khoản chỉ là dùng hạn mức của tài khoản khác do chính
/// người dùng đăng nhập.
extension AINameExtractionBatchProcessor {
    /// Báo tiến độ khi đang chờ giới hạn mỗi chừng này giây (dải tiến độ tự đếm từng giây).
    private static let rateLimitProgressInterval: TimeInterval = 15

    /// Gửi một lượt (qua `extractTurnRetryingEmpty`), xử lý giới hạn của Chế độ AI như mô tả ở đầu file.
    func extractTurnHandlingRateLimit(
        _ turn: AINameScanFailedBatch,
        turnLabel: String,
        providerSwitch: GoogleAccountRotation,
        promptOverride: String?,
        conversationId: UUID?,
        progress: inout AINameScanProgress,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws -> (names: [AIExtractedName], saidNoNames: Bool) {
        while true {
            let config = providerSwitch.config
            do {
                let reply = try await extractTurnRetryingEmpty(
                    turn,
                    turnLabel: turnLabel,
                    config: config,
                    promptOverride: promptOverride,
                    conversationId: conversationId
                )
                providerSwitch.recordSuccess()
                return reply
            } catch let error as GoogleAIModeError where config.activeProfile.isGoogleAIMode && !Task.isCancelled {
                guard providerSwitch.treatsAsRateLimit(error) else { throw error }
                if let account = providerSwitch.rotateToNextAccount(),
                   await GoogleSessionSwitcher.shared.apply(account: account) {
                    await GoogleAIModeTurnQueue.shared.clearRateLimitBlock()
                    AppLogger.shared.log("❌ 🤖 [AIMode] Quét tên riêng: Chế độ AI bị Google giới hạn ở \(turnLabel) (\(error.localizedDescription)) — tráo sang tài khoản \"\(account.label)\", gửi lại lượt này")
                    progress.switchedProviderName = account.label
                    onProgress(progress, nil)
                    continue
                }
                if let name = providerSwitch.switchToGeminiWeb() {
                    AppLogger.shared.log("❌ 🤖 [AIMode] Quét tên riêng: hết tài khoản Google để tráo ở \(turnLabel) — chuyển sang \(name), gửi lại lượt này")
                    progress.switchedProviderName = name
                    onProgress(progress, nil)
                    continue
                }
                guard let wait = providerSwitch.nextWait() else {
                    AppLogger.shared.log("❌ 🤖 [AIMode] Quét tên riêng: đã chờ hết \(GoogleAccountRotation.rateLimitWaits.count) nấc mà Chế độ AI vẫn bị giới hạn ở \(turnLabel) — dừng")
                    throw GoogleAIModeError.rateLimitExhausted(waitedMinutes: GoogleAccountRotation.totalWaitMinutes)
                }
                var retryAfter: TimeInterval = 0
                if case .rateLimited(let seconds) = error {
                    retryAfter = TimeInterval(seconds)
                }
                try await waitForRateLimit(
                    seconds: max(wait.seconds, retryAfter),
                    attempt: wait.attempt,
                    total: wait.total,
                    turnLabel: turnLabel,
                    progress: &progress,
                    onProgress: onProgress
                )
            }
        }
    }

    /// Chờ hạn chờ giới hạn (huỷ được — bấm Dừng ⇒ `CancellationError`), báo tiến độ đếm ngược theo nhịp.
    private func waitForRateLimit(
        seconds: TimeInterval,
        attempt: Int,
        total: Int,
        turnLabel: String,
        progress: inout AINameScanProgress,
        onProgress: @escaping @Sendable (AINameScanProgress, [AIExtractedName]?) -> Void
    ) async throws {
        let until = Date().addingTimeInterval(seconds)
        await GoogleAIModeTurnQueue.shared.noteRateLimited(until: until)
        AppLogger.shared.log("❌ 🤖 [AIMode] Quét tên riêng: Chế độ AI bị Google giới hạn ở \(turnLabel), không có profile Gemini Web — chờ \(Int(seconds)) s (lần \(attempt)/\(total)) rồi gửi lại \(GeminiWebForegroundGate.shared.appStateLabel)")
        progress.rateLimitWaitUntil = until
        progress.rateLimitWaitAttempt = attempt
        progress.rateLimitWaitTotal = total
        while true {
            let remaining = until.timeIntervalSinceNow
            guard remaining > 0 else { break }
            onProgress(progress, nil)
            try await Task.sleep(nanoseconds: UInt64(min(Self.rateLimitProgressInterval, remaining) * 1_000_000_000))
        }
        progress.rateLimitWaitUntil = nil
        progress.rateLimitWaitAttempt = 0
        progress.rateLimitWaitTotal = 0
        onProgress(progress, nil)
        AppLogger.shared.log("🤖 [AIMode] Quét tên riêng: hết lần chờ \(attempt)/\(total) — gửi lại \(turnLabel)")
    }
}
