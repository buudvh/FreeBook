import Foundation

/// Một lượt Chế độ AI của Google (1.3.609): xếp hàng → mở trang/gửi câu hỏi → đọc DOM theo nhịp → phát chữ → xong.
///
/// - **Xong** khi: số lượt trên trang tăng so với trước khi gửi, chữ của lượt mới đứng yên ≥ `settleSeconds` **và** vùng
///   trạng thái báo "sẵn sàng" sau khi đã thấy nó tắt; hoặc đứng yên ≥ `fallbackSettleSeconds` (trang khôi phục còn chữ
///   "sẵn sàng" của lượt cũ nên không tin ngay chữ đó).
/// - Chỉ xét **lượt mới nhất**: chữ lỗi của trang trong lượt đó ⇒ `generationFailed`; chữ trả lời lẫn nhãn của prompt ⇒
///   `protocolChanged` (tránh dòng mẫu `Tên gốc=Nghĩa` thành name).
/// - Phát chữ theo tiền tố, chỉ các dòng đã trọn; lúc xong mà bản cuối không nối tiếp phần đã phát thì nối bản cuối sau
///   dấu "— Chế độ AI sửa lại câu trả lời —" (coordinator cộng dồn delta, như Gemini Web).
/// - Retry đúng một tầng: một lần khi `isRetryable` (chỉ còn trả rỗng, 1.3.612) **và chưa phát chữ nào**, lặp lại đúng
///   loại lượt (lượt mới thì mở lại, lượt nối tiếp thì khôi phục `mstk` mới nhất rồi gửi lại — không lặng lẽ mở cuộc
///   chat mới). Câu "đã đạt đến giới hạn" của Google ⇒ `rateLimited` + hạn chờ toàn cục, không bao giờ gửi lại.
extension GoogleAIModeClient {
    enum TurnKind: Sendable {
        /// Cuộc chat mới, câu hỏi trong URL.
        case fresh(String)
        /// Mở lại cuộc chat bằng `mstk` rồi gửi `text` qua ô nhập.
        case continuation(mstk: String, text: String)
    }

    private static let pollInterval: UInt64 = 300_000_000
    private static let settleSeconds: TimeInterval = 2
    private static let fallbackSettleSeconds: TimeInterval = 8
    private static let restoreTimeout: TimeInterval = 15
    /// Gửi bằng Enter mà quá chừng này chưa có lượt mới ⇒ bấm nút "Gửi" (một lần).
    private static let sendClickFallbackSeconds: TimeInterval = 4
    /// Chưa tới chừng này ký tự thì chưa phát chữ (trang có thể đang hiện chữ chờ ngắn).
    private static let minStreamLength = 24
    /// Hạn chờ mặc định khi trang báo hết hạn mức số câu trả lời AI ("thử lại sau giây lát") — vòng quét tự kéo dài
    /// theo nấc chờ của nó (1.3.612).
    private static let rateLimitCooldown: TimeInterval = 60

    /// Quan sát một lượt, dùng chung giữa các lần thử: đã phát chữ chưa, `mstk` mới nhất trang để lộ.
    final class TurnProgress: @unchecked Sendable {
        private let lock = NSLock()
        private var didEmit = false
        private var latestMstk: String?

        var emitted: Bool {
            lock.lock(); defer { lock.unlock() }
            return didEmit
        }

        var mstk: String? {
            lock.lock(); defer { lock.unlock() }
            return latestMstk
        }

        func markEmitted() {
            lock.lock(); didEmit = true; lock.unlock()
        }

        func record(mstk: String) {
            lock.lock(); latestMstk = mstk; lock.unlock()
        }
    }

    func runTurn(
        _ kind: TurnKind,
        isScan: Bool,
        timeouts: Timeouts,
        onDelta: (@Sendable (String) -> Void)?,
        onMstk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let observation = TurnProgress()
        var request = kind
        var attempt = 0
        while true {
            let current = request
            do {
                return try await GoogleAIModeTurnQueue.shared.run(isScan: isScan) {
                    try await self.performTurn(current, timeouts: timeouts, observation: observation, onDelta: onDelta, onMstk: onMstk)
                }
            } catch let error as GoogleAIModeError where attempt == 0 && error.isRetryable && !observation.emitted {
                attempt += 1
                AppLogger.shared.log("🤖 [AIMode] Lượt lỗi (\(error.localizedDescription)) — thử lại 1 lần")
                if case .continuation(_, let text) = request, let latest = observation.mstk {
                    request = .continuation(mstk: latest, text: text)
                }
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func performTurn(
        _ kind: TurnKind,
        timeouts: Timeouts,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?,
        onMstk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await GoogleAIModeSessionController.shared
        let token = await controller.beginTurn()
        do {
            let text = try await withTaskCancellationHandler {
                try await self.driveTurn(kind, timeouts: timeouts, observation: observation, onDelta: onDelta, onMstk: onMstk)
            } onCancel: {
                Task { @MainActor in GoogleAIModeSessionController.shared.abort(token: token) }
            }
            await controller.endTurn(token: token)
            return text
        } catch {
            if Task.isCancelled {
                await controller.abort(token: token)
            }
            await controller.endTurn(token: token)
            throw error
        }
    }

    private func driveTurn(
        _ kind: TurnKind,
        timeouts: Timeouts,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?,
        onMstk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await GoogleAIModeSessionController.shared
        var baseline = 0
        var submitted = false
        var knownMstk = ""
        switch kind {
        case .fresh(let prompt):
            guard let url = GoogleAIModePageContract.freshURL(prompt: prompt) else {
                throw GoogleAIModeError.protocolChanged("không dựng được URL câu hỏi")
            }
            AppLogger.shared.log("🤖 [AIMode] Lượt mới: \(prompt.count) ký tự, \(GoogleAIModePageContract.encodedLength(prompt)) byte")
            try await controller.navigate(to: url)
        case .continuation(let mstk, let text):
            guard let url = GoogleAIModePageContract.restoreURL(mstk: mstk) else {
                throw GoogleAIModeError.protocolChanged("không dựng được URL khôi phục")
            }
            AppLogger.shared.log("🤖 [AIMode] Nối tiếp cuộc chat: \(text.count) ký tự, mstk=\(mstk.prefix(6))")
            try await controller.navigate(to: url)
            baseline = try await waitForRestoredThread()
            guard await controller.submit(text) else {
                AppLogger.shared.log("🤖 [AIMode] Không thấy ô hỏi tiếp sau khi khôi phục cuộc chat")
                throw GoogleAIModeError.threadUnavailable
            }
            submitted = true
            knownMstk = mstk
        }
        return try await readAnswer(
            baseline: baseline,
            submitted: submitted,
            knownMstk: knownMstk,
            timeouts: timeouts,
            observation: observation,
            onDelta: onDelta,
            onMstk: onMstk
        )
    }

    /// Trang khôi phục phải hiện ít nhất một lượt cũ và ô nhập; trả số lượt lúc đó (mốc để nhận ra lượt mới).
    private func waitForRestoredThread() async throws -> Int {
        let controller = await GoogleAIModeSessionController.shared
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < Self.restoreTimeout {
            try Task.checkCancellation()
            if await controller.verificationRequired { throw GoogleAIModeError.captchaRequired }
            if let snapshot = await controller.snapshot() {
                if GoogleAIModePageContract.isVerificationPath(snapshot.path) { throw GoogleAIModeError.captchaRequired }
                if snapshot.turnCount > 0, snapshot.composerFound {
                    AppLogger.shared.log("🤖 [AIMode] Đã khôi phục cuộc chat: \(snapshot.turnCount) lượt sau \(Int(Date().timeIntervalSince(startedAt) * 1000)) ms")
                    return snapshot.turnCount
                }
            }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }
        AppLogger.shared.log("🤖 [AIMode] Khôi phục cuộc chat không ra lượt nào sau \(Int(Self.restoreTimeout)) s")
        throw GoogleAIModeError.threadUnavailable
    }

    /// `knownMstk`: token đã biết của cuộc chat (lượt nối tiếp) — trang khôi phục hiện lại token đó, không phải token mới.
    private func readAnswer(
        baseline: Int,
        submitted: Bool,
        knownMstk: String,
        timeouts: Timeouts,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?,
        onMstk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let controller = await GoogleAIModeSessionController.shared
        let startedAt = Date()
        var lastActivity = startedAt
        var lastRaw = ""
        var lastTurnCount = -1
        var emitted = ""
        var sawReadyOff = false
        var sawNewTurn = false
        var clickedSend = false
        var lastMstk = knownMstk
        var missingSnapshots = 0
        var answerFound = false

        while true {
            try Task.checkCancellation()
            if await controller.verificationRequired { throw GoogleAIModeError.captchaRequired }
            let now = Date()
            guard let snapshot = await controller.snapshot() else {
                missingSnapshots += 1
                if missingSnapshots >= 20 {
                    let alive = await controller.hasWebView
                    if !alive { throw GoogleAIModeError.webViewUnavailable }
                }
                try await Task.sleep(nanoseconds: Self.pollInterval)
                continue
            }
            missingSnapshots = 0
            if GoogleAIModePageContract.isVerificationPath(snapshot.path) { throw GoogleAIModeError.captchaRequired }
            // Hết hạn mức số câu trả lời AI (1.3.612): chặn mọi lượt một lúc, không gửi lại. Câu giới hạn trong khối lượt
            // chỉ tính khi đó là lượt mới — trang khôi phục còn lượt cũ.
            if snapshot.pageRateLimited || (snapshot.turnCount > baseline && snapshot.newestRateLimited) {
                AppLogger.shared.log("❌ 🤖 [AIMode] Google báo hết hạn mức số câu trả lời AI sau \(Self.ms(since: startedAt)) ms — chặn mọi lượt \(Int(Self.rateLimitCooldown)) s \(GeminiWebForegroundGate.shared.appStateLabel); trang: «\(snapshot.errorSnippet)»")
                await GoogleAIModeTurnQueue.shared.noteRateLimited(for: Self.rateLimitCooldown)
                throw GoogleAIModeError.rateLimited(retryAfter: Int(Self.rateLimitCooldown))
            }
            if !snapshot.mstk.isEmpty, snapshot.mstk != lastMstk {
                lastMstk = snapshot.mstk
                observation.record(mstk: snapshot.mstk)
                onMstk?(snapshot.mstk)
            }
            if !snapshot.readyStatus { sawReadyOff = true }
            if snapshot.turnCount != lastTurnCount {
                lastTurnCount = snapshot.turnCount
                lastActivity = now
            }

            if snapshot.turnCount > baseline {
                if !sawNewTurn {
                    sawNewTurn = true
                    AppLogger.shared.log("🤖 [AIMode] Thấy lượt trả lời mới sau \(Self.ms(since: startedAt)) ms")
                }
                if snapshot.newestHasError {
                    AppLogger.shared.log("❌ 🤖 [AIMode] Trang báo lỗi trong lượt mới sau \(Self.ms(since: startedAt)) ms; trang: «\(snapshot.errorSnippet)»")
                    throw GoogleAIModeError.generationFailed
                }
                answerFound = answerFound || snapshot.answerFound
                if snapshot.newestText != lastRaw {
                    lastRaw = snapshot.newestText
                    lastActivity = now
                }
                if let onDelta {
                    let streamable = GoogleAIModePageContract.streamablePrefix(lastRaw)
                    if GoogleAIModePageContract.containsPromptEcho(streamable) {
                        throw GoogleAIModeError.protocolChanged("phần trả lời lẫn câu hỏi")
                    }
                    if streamable.count >= Self.minStreamLength,
                       streamable.unicodeScalars.count > emitted.unicodeScalars.count,
                       streamable.unicodeScalars.starts(with: emitted.unicodeScalars) {
                        let suffix = String(String.UnicodeScalarView(streamable.unicodeScalars.dropFirst(emitted.unicodeScalars.count)))
                        emitted = streamable
                        observation.markEmitted()
                        onDelta(suffix)
                    }
                }
                let stable = now.timeIntervalSince(lastActivity)
                let hasText = !lastRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let readySettled = stable >= Self.settleSeconds && snapshot.readyStatus && sawReadyOff
                if hasText, readySettled || stable >= Self.fallbackSettleSeconds {
                    // Ghi rõ luật nào kết thúc lượt: luật đứng yên 8 s có thể nhận nhầm chữ chờ của trang — chỉnh theo log.
                    let rule = readySettled ? "trạng thái sẵn sàng" : "đứng yên \(Int(Self.fallbackSettleSeconds)) s"
                    return try finish(lastRaw, emitted: emitted, observation: observation, onDelta: onDelta, startedAt: startedAt, turns: snapshot.turnCount, rule: rule)
                }
            } else if submitted, !clickedSend, now.timeIntervalSince(startedAt) >= Self.sendClickFallbackSeconds {
                clickedSend = true
                let clicked = await controller.clickSend()
                AppLogger.shared.log("🤖 [AIMode] Enter chưa tạo lượt mới sau \(Int(Self.sendClickFallbackSeconds)) s — bấm nút Gửi: \(clicked ? "được" : "không thấy nút")")
            }

            let idle = now.timeIntervalSince(lastActivity)
            let total = now.timeIntervalSince(startedAt)
            if idle > timeouts.idle || total > timeouts.absolute {
                let scriptNote = snapshot.scriptError.map { ", lỗi JS: \($0)" } ?? ""
                AppLogger.shared.log("❌ 🤖 [AIMode] Hết thời gian chờ (idle \(Int(idle))/\(Int(timeouts.idle)) s, tổng \(Int(total))/\(Int(timeouts.absolute)) s, lượt=\(snapshot.turnCount)/\(baseline), chữ=\(lastRaw.count), trang=\(snapshot.bodyLength) ký tự\(scriptNote)) \(GeminiWebForegroundGate.shared.appStateLabel)")
                if !sawNewTurn {
                    throw GoogleAIModeError.protocolChanged("không thấy lượt trả lời mới [data-scope-id=turn]")
                }
                if !answerFound {
                    throw GoogleAIModeError.protocolChanged("không thấy [data-subtree=aimc] trong lượt mới")
                }
                throw GoogleAIModeError.timeout
            }
            try await Task.sleep(nanoseconds: Self.pollInterval)
        }
    }

    /// Làm sạch bản cuối, kiểm tra, phát nốt phần còn lại.
    private func finish(
        _ raw: String,
        emitted: String,
        observation: TurnProgress,
        onDelta: (@Sendable (String) -> Void)?,
        startedAt: Date,
        turns: Int,
        rule: String
    ) throws -> String {
        let final = GoogleAIModePageContract.cleanAnswer(raw)
        if GoogleAIModePageContract.containsPromptEcho(final) {
            throw GoogleAIModeError.protocolChanged("phần trả lời lẫn câu hỏi")
        }
        guard !final.isEmpty else { throw GoogleAIModeError.emptyResponse }
        if let onDelta {
            if final.unicodeScalars.starts(with: emitted.unicodeScalars) {
                let suffix = String(String.UnicodeScalarView(final.unicodeScalars.dropFirst(emitted.unicodeScalars.count)))
                if !suffix.isEmpty {
                    observation.markEmitted()
                    onDelta(suffix)
                }
            } else {
                onDelta("\n\n— Chế độ AI sửa lại câu trả lời —\n\(final)")
            }
        }
        AppLogger.shared.log("🤖 [AIMode] Lượt xong sau \(Self.ms(since: startedAt)) ms (theo \(rule)), \(final.count) ký tự, \(turns) lượt trên trang")
        return final
    }

    private static func ms(since date: Date) -> Int {
        Int(Date().timeIntervalSince(date) * 1000)
    }
}
