import Foundation

/// Một lượt ChatGPT Web (1.3.971): xếp hàng → mở trang / dùng lại trang → gán câu hỏi, gửi form → đọc DOM theo nhịp →
/// phát chữ → xong.
///
/// - Chạy trên cả trang ẩn danh lẫn trang đã đăng nhập (`ChatGPTWebPageContract` che khác biệt).
/// - **Xong** khi tin trợ lý mới (số tin tăng so với trước khi gửi) đã `complete` và chữ đứng yên ≥
///   `settleSeconds`; dự phòng: không còn dấu hiệu đang viết và chữ đứng yên ≥ `fallbackSettleSeconds`. **Không** chờ nút
///   gửi trở lại (thử thật: chậm ~3 s sau khi tin đã xong).
/// - Cổng chặn của trang (`[data-gate-kind]`) ⇒ lỗi tương ứng ngay, không gửi lại; `rate_limited` đặt hạn chờ toàn cục.
/// - Phát chữ theo tiền tố, chỉ các dòng đã trọn; lúc xong mà bản cuối không nối tiếp phần đã phát thì nối bản cuối sau
///   dấu "— ChatGPT sửa lại câu trả lời —" (coordinator cộng dồn delta, như Gemini Web).
/// - Retry đúng một tầng: một lần khi `isRetryable` (trả rỗng) **và chưa phát chữ nào**, lặp lại đúng loại lượt.
/// - App **không** tự đóng hộp mời đăng nhập của ChatGPT: hộp đang mở mà lượt không bắt đầu ⇒ `loginPrompt`.
extension ChatGPTWebClient {
    enum TurnKind: Sendable {
        /// Cuộc chat mới: nạp trang chủ rồi gửi `prompt`.
        case fresh(String)
        /// Hỏi tiếp trong trang đang giữ cuộc chat của phiên `sessionId`.
        case continuation(sessionId: UUID, text: String)
    }

    private static let pollInterval: UInt64 = 300_000_000
    /// Lượt không phát chữ (quét tên riêng, ping thử): đọc trang mỗi giây.
    private static let quietPollInterval: UInt64 = 1_000_000_000
    private static let settleSeconds: TimeInterval = 1
    private static let fallbackSettleSeconds: TimeInterval = 8
    /// Tin đã `complete` mà vẫn rỗng sau chừng này ⇒ `emptyResponse`.
    private static let emptySettleSeconds: TimeInterval = 4
    private static let composerTimeout: TimeInterval = 30
    /// Ô nhập đã có mà script của trang chưa báo sẵn sàng quá chừng này ⇒ vẫn gửi.
    private static let readyGraceSeconds: TimeInterval = 3
    /// Chờ nút gửi của trang đã đăng nhập xuất hiện sau khi gán chữ.
    private static let submitButtonTimeout: TimeInterval = 3
    /// Lượt mới của trang đã đăng nhập mang trạng thái lạ (không `complete` / `in_progress`) quá chừng này ⇒ lượt lỗi.
    private static let turnFailureSeconds: TimeInterval = 3
    /// Trang kiểm tra của Cloudflare thường tự qua trong vài giây; quá chừng này ⇒ `captchaRequired`.
    private static let challengeTimeout: TimeInterval = 15
    /// Trang đang mở còn viết lượt trước: chờ tối đa chừng này rồi mới hỏi tiếp.
    private static let idleThreadTimeout: TimeInterval = 8
    /// Gửi rồi mà quá chừng này chưa có lượt mới và chữ còn nằm trong ô nhập ⇒ gửi lại form (một lần).
    private static let resubmitSeconds: TimeInterval = 4
    /// Hộp mời đăng nhập đang mở mà quá chừng này lượt chưa bắt đầu ⇒ `loginPrompt`.
    private static let loginPromptSeconds: TimeInterval = 8
    /// Chưa tới chừng này ký tự thì chưa phát chữ.
    private static let minStreamLength = 24
    /// Hạn chờ khi ChatGPT báo hết lượt mà không cho biết bao lâu.
    private static let defaultRateLimitCooldown: TimeInterval = 300

    /// Quan sát một lượt, dùng chung giữa các lần thử: đã phát chữ chưa.
    final class TurnProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var didEmit = false

        var emitted: Bool {
            lock.lock(); defer { lock.unlock() }
            return didEmit
        }

        func markEmitted() {
            lock.lock(); didEmit = true; lock.unlock()
        }
    }

    /// `live` khác nil = lượt chat: thành công thì trang được giữ cho lượt kế của phiên đó.
    func runTurn(
        _ kind: TurnKind,
        isScan: Bool,
        timeouts: Timeouts,
        live: ChatGPTWebLiveSession?,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let observation = TurnProgress()
        var attempt = 0
        while true {
            do {
                return try await ChatGPTWebTurnQueue.shared.run(isScan: isScan) {
                    try await self.performTurn(kind, timeouts: timeouts, live: live, observation: observation, onDelta: onDelta)
                }
            } catch let error as ChatGPTWebError where attempt == 0 && error.isRetryable && !observation.emitted {
                attempt += 1
                AppLogger.shared.log("🤖 [ChatGPTWeb] Lượt lỗi (\(error.localizedDescription)) — thử lại 1 lần")
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func performTurn(
        _ kind: TurnKind,
        timeouts: Timeouts,
        live: ChatGPTWebLiveSession?,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await ChatGPTWebSessionController.shared
        let token = await controller.beginTurn()
        do {
            let text = try await withTaskCancellationHandler {
                try await self.driveTurn(kind, timeouts: timeouts, observation: observation, onDelta: onDelta)
            } onCancel: {
                Task { @MainActor in ChatGPTWebSessionController.shared.abort(token: token) }
            }
            await controller.endTurn(token: token, live: live)
            return text
        } catch {
            if Task.isCancelled {
                await controller.abort(token: token)
            }
            await controller.endTurn(token: token, live: nil)
            if let failure = error as? ChatGPTWebError, case .rateLimited(let retryAfter) = failure {
                let cooldown = retryAfter > 0 ? TimeInterval(retryAfter) : Self.defaultRateLimitCooldown
                await ChatGPTWebTurnQueue.shared.noteRateLimited(for: cooldown)
            }
            throw error
        }
    }

    private func driveTurn(
        _ kind: TurnKind,
        timeouts: Timeouts,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await ChatGPTWebSessionController.shared
        let baseline: Int
        let prompt: String
        switch kind {
        case .fresh(let text):
            AppLogger.shared.log("🤖 [ChatGPTWeb] Lượt mới: \(text.count) ký tự")
            try await controller.navigate(to: ChatGPTWebPageContract.homeURL)
            try await waitForComposer()
            baseline = 0
            prompt = text
        case .continuation(let sessionId, let text):
            let liveId = await controller.liveSession?.sessionId
            guard liveId == sessionId else {
                AppLogger.shared.log("🤖 [ChatGPTWeb] Trang không còn giữ cuộc chat của phiên \(sessionId.uuidString.prefix(8))")
                throw ChatGPTWebError.threadUnavailable
            }
            AppLogger.shared.log("🤖 [ChatGPTWeb] Hỏi tiếp trong trang: \(text.count) ký tự")
            baseline = try await waitForIdleThread()
            prompt = text
        }

        guard await controller.fill(prompt) else {
            throw ChatGPTWebError.protocolChanged("không gán được chữ vào ô nhập")
        }
        // Trang đã đăng nhập chỉ dựng nút gửi sau khi ô nhập có chữ ⇒ chờ nút một lúc.
        var outcome = await controller.submit()
        let submitStartedAt = Date()
        while outcome == .noSubmit, Date().timeIntervalSince(submitStartedAt) < Self.submitButtonTimeout {
            try await Task.sleep(nanoseconds: Self.pollInterval)
            outcome = await controller.submit()
        }
        guard outcome.didSend else {
            AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Không gửi được form: \(outcome.rawValue)")
            throw ChatGPTWebError.protocolChanged("không gửi được form (\(outcome.rawValue))")
        }
        return try await readAnswer(baseline: baseline, timeouts: timeouts, observation: observation, onDelta: onDelta)
    }

    /// Trang chủ vừa nạp: chờ ô nhập (và script của trang). Trang kiểm tra Cloudflare được chờ tự qua tới `challengeTimeout`.
    private func waitForComposer() async throws {
        let controller = await ChatGPTWebSessionController.shared
        let startedAt = Date()
        var composerSeenAt: Date?
        var challengeSeenAt: Date?
        while Date().timeIntervalSince(startedAt) < Self.composerTimeout {
            try Task.checkCancellation()
            if let snapshot = await controller.snapshot() {
                if snapshot.gated {
                    AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Trang hiện cổng chặn ngay lúc mở (\(snapshot.gateKind)): «\(snapshot.gateText)»")
                    throw ChatGPTWebPageContract.gateError(snapshot)
                }
                if snapshot.composerFound {
                    let seenAt = composerSeenAt ?? Date()
                    composerSeenAt = seenAt
                    if snapshot.ready || Date().timeIntervalSince(seenAt) >= Self.readyGraceSeconds {
                        await controller.notePageKind(signedIn: snapshot.signedIn)
                        AppLogger.shared.log("🤖 [ChatGPTWeb] Ô nhập sẵn sàng sau \(Self.ms(since: startedAt)) ms (trang \(snapshot.kindLabel), script trang sẵn sàng=\(snapshot.ready), hộp thoại mở=\(snapshot.dialogOpen))")
                        return
                    }
                } else if snapshot.challenge {
                    let seenAt = challengeSeenAt ?? Date()
                    challengeSeenAt = seenAt
                    if Date().timeIntervalSince(seenAt) >= Self.challengeTimeout {
                        AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Trang kiểm tra của Cloudflare không tự qua sau \(Int(Self.challengeTimeout)) s \(GeminiWebForegroundGate.shared.appStateLabel)")
                        throw ChatGPTWebError.captchaRequired
                    }
                }
            } else {
                let alive = await controller.hasWebView
                if !alive { throw ChatGPTWebError.webViewUnavailable }
            }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }
        if challengeSeenAt != nil { throw ChatGPTWebError.captchaRequired }
        AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Không thấy ô nhập sau \(Int(Self.composerTimeout)) s \(GeminiWebForegroundGate.shared.appStateLabel)")
        throw ChatGPTWebError.protocolChanged("không thấy ô nhập của trang ẩn danh lẫn trang đã đăng nhập")
    }

    /// Trang đang mở phải còn ô nhập, còn ít nhất một tin trợ lý, không cổng chặn, không hộp thoại và đã viết xong lượt
    /// trước; trả số tin trợ lý lúc đó (mốc để nhận ra tin mới). Không đạt ⇒ `threadUnavailable`.
    private func waitForIdleThread() async throws -> Int {
        let controller = await ChatGPTWebSessionController.shared
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < Self.idleThreadTimeout {
            try Task.checkCancellation()
            guard let snapshot = await controller.snapshot() else { break }
            guard snapshot.composerFound, snapshot.turnCount > 0, !snapshot.gated, !snapshot.dialogOpen, snapshot.submitError.isEmpty else {
                AppLogger.shared.log("🤖 [ChatGPTWeb] Trang không hỏi tiếp được (ô nhập=\(snapshot.composerFound), tin=\(snapshot.turnCount), cổng chặn=\(snapshot.gated), hộp thoại mở=\(snapshot.dialogOpen))")
                throw ChatGPTWebError.threadUnavailable
            }
            if !snapshot.generating, !snapshot.streaming { return snapshot.turnCount }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Trang vẫn đang viết lượt trước sau \(Int(Self.idleThreadTimeout)) s — không hỏi tiếp trong trang")
        throw ChatGPTWebError.threadUnavailable
    }

    private func readAnswer(
        baseline: Int,
        timeouts: Timeouts,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await ChatGPTWebSessionController.shared
        let startedAt = Date()
        var lastAlive = startedAt
        var lastChange = startedAt
        var lastRaw = ""
        var emitted = ""
        var sawNewTurn = false
        var answerFound = false
        var resubmitted = false
        var missingSnapshots = 0
        let interval = onDelta == nil ? Self.quietPollInterval : Self.pollInterval

        while true {
            try Task.checkCancellation()
            let now = Date()
            guard let snapshot = await controller.snapshot() else {
                missingSnapshots += 1
                if missingSnapshots >= 20 {
                    let alive = await controller.hasWebView
                    if !alive { throw ChatGPTWebError.webViewUnavailable }
                }
                try await Task.sleep(nanoseconds: interval)
                continue
            }
            missingSnapshots = 0
            if snapshot.gated {
                AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Trang hiện cổng chặn (\(snapshot.gateKind), thử lại sau=\(snapshot.retryAfter)) sau \(Self.ms(since: startedAt)) ms \(GeminiWebForegroundGate.shared.appStateLabel); trang: «\(snapshot.gateText)»")
                throw ChatGPTWebPageContract.gateError(snapshot)
            }
            if !snapshot.submitError.isEmpty {
                AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Trang báo lỗi gửi sau \(Self.ms(since: startedAt)) ms; trang: «\(snapshot.submitError)»")
                throw ChatGPTWebError.generationFailed(snapshot.submitError)
            }
            let elapsed = now.timeIntervalSince(startedAt)

            if snapshot.turnCount > baseline {
                if !sawNewTurn {
                    sawNewTurn = true
                    lastChange = now
                    AppLogger.shared.log("🤖 [ChatGPTWeb] Thấy tin trả lời mới sau \(Self.ms(since: startedAt)) ms")
                }
                answerFound = answerFound || snapshot.answerFound
                if snapshot.newestText != lastRaw {
                    lastRaw = snapshot.newestText
                    lastChange = now
                    lastAlive = now
                } else if snapshot.streaming || (snapshot.generating && !snapshot.complete) {
                    lastAlive = now
                }
                if let onDelta {
                    let streamable = ChatGPTWebPageContract.streamablePrefix(lastRaw)
                    if streamable.count >= Self.minStreamLength,
                       streamable.unicodeScalars.count > emitted.unicodeScalars.count,
                       streamable.unicodeScalars.starts(with: emitted.unicodeScalars) {
                        let suffix = String(String.UnicodeScalarView(streamable.unicodeScalars.dropFirst(emitted.unicodeScalars.count)))
                        emitted = streamable
                        observation.markEmitted()
                        onDelta(suffix)
                    }
                }
                let stable = now.timeIntervalSince(lastChange)
                let hasText = !lastRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !snapshot.turnFailure.isEmpty, stable >= Self.turnFailureSeconds {
                    AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Lượt mới mang trạng thái «\(snapshot.turnFailure)» sau \(Self.ms(since: startedAt)) ms (chữ=\(lastRaw.count))")
                    throw ChatGPTWebError.generationFailed("trạng thái lượt: \(snapshot.turnFailure)")
                }
                if snapshot.complete {
                    if hasText, stable >= Self.settleSeconds {
                        return try finish(lastRaw, emitted: emitted, observation: observation, onDelta: onDelta, startedAt: startedAt, rule: "tin đã xong")
                    }
                    if !hasText, stable >= Self.emptySettleSeconds {
                        AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Tin trả lời xong mà rỗng sau \(Self.ms(since: startedAt)) ms (khối chữ=\(snapshot.answerFound))")
                        throw ChatGPTWebError.emptyResponse
                    }
                } else if hasText, !snapshot.streaming, !snapshot.generating, stable >= Self.fallbackSettleSeconds {
                    // Ghi rõ luật nào kết thúc lượt: luật đứng yên 8 s có thể cắt sớm một câu trả lời đang nghĩ — chỉnh theo log.
                    return try finish(lastRaw, emitted: emitted, observation: observation, onDelta: onDelta, startedAt: startedAt, rule: "đứng yên \(Int(Self.fallbackSettleSeconds)) s")
                }
            } else if snapshot.generating {
                lastAlive = now
            } else {
                if !resubmitted, elapsed >= Self.resubmitSeconds, snapshot.draftLength > 0 {
                    resubmitted = true
                    let outcome = await controller.submit()
                    AppLogger.shared.log("🤖 [ChatGPTWeb] Gửi rồi mà \(Int(Self.resubmitSeconds)) s chưa có lượt mới, chữ còn trong ô nhập — gửi lại form: \(outcome.rawValue) (hộp thoại mở=\(snapshot.dialogOpen))")
                }
                if snapshot.dialogOpen, elapsed >= Self.loginPromptSeconds {
                    AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Hộp mời đăng nhập đang mở và lượt không bắt đầu sau \(Int(Self.loginPromptSeconds)) s")
                    throw ChatGPTWebError.loginPrompt
                }
            }

            let idle = now.timeIntervalSince(lastAlive)
            if idle > timeouts.idle || elapsed > timeouts.absolute {
                let scriptNote = snapshot.scriptError.map { ", lỗi JS: \($0)" } ?? ""
                AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Hết thời gian chờ (idle \(Int(idle))/\(Int(timeouts.idle)) s, tổng \(Int(elapsed))/\(Int(timeouts.absolute)) s, tin=\(snapshot.turnCount)/\(baseline), chữ=\(lastRaw.count), đang viết=\(snapshot.streaming || snapshot.generating), trang=\(snapshot.path)\(scriptNote)) \(GeminiWebForegroundGate.shared.appStateLabel)")
                if !sawNewTurn {
                    throw ChatGPTWebError.protocolChanged("không thấy tin trả lời mới (trang \(snapshot.kindLabel))")
                }
                if !answerFound {
                    throw ChatGPTWebError.protocolChanged("không thấy khối chữ trong tin mới (trang \(snapshot.kindLabel))")
                }
                throw ChatGPTWebError.timeout
            }
            try await Task.sleep(nanoseconds: interval)
        }
    }

    /// Làm sạch bản cuối, kiểm tra, phát nốt phần còn lại.
    private func finish(
        _ raw: String,
        emitted: String,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?,
        startedAt: Date,
        rule: String
    ) throws -> String {
        let final = ChatGPTWebPageContract.cleanAnswer(raw)
        guard !final.isEmpty else { throw ChatGPTWebError.emptyResponse }
        if let onDelta {
            if final.unicodeScalars.starts(with: emitted.unicodeScalars) {
                let suffix = String(String.UnicodeScalarView(final.unicodeScalars.dropFirst(emitted.unicodeScalars.count)))
                if !suffix.isEmpty {
                    observation.markEmitted()
                    onDelta(suffix)
                }
            } else {
                onDelta("\n\n— ChatGPT sửa lại câu trả lời —\n\(final)")
            }
        }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Lượt xong sau \(Self.ms(since: startedAt)) ms (theo \(rule)), \(final.count) ký tự")
        return final
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
