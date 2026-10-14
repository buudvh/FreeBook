import Foundation

/// Chat trong Reader **nối tiếp** một cuộc chat Gemini cho mỗi phiên chat của app (1.3.514).
///
/// - Lượt đầu (hoặc khi phải mở cuộc chat mới) gửi đủ ngữ cảnh như trước (`GeminiWebPromptFormatter.buildPrompt`).
/// - Lượt sau chỉ gửi tin mới của người dùng; khối ngữ cảnh hệ thống đổi (sang chương khác, đổi chế độ, đổi từ
///   điển…) thì gửi kèm "Cập nhật ngữ cảnh".
/// - Mở cuộc chat mới khi: chưa có, đổi model (Google trả 1050 nếu đổi giữa chừng), đổi công tắc lưu lịch sử.
/// - Lượt nối tiếp bị Google từ chối trước khi có chữ nào (vd. cuộc chat đã xoá trên web) ⇒ chat thường mở lại cuộc
///   chat mới với đủ ngữ cảnh, đúng một lần. Lỗi tài khoản/hạn mức thì không thử lại.
/// - Lượt quét tên riêng (`forceContext`, 1.3.527): phiên **đã có** cuộc chat (cid) thì **không bao giờ** mở cuộc chat
///   mới — bị từ chối thì chờ 5 s, thử lại đúng lượt nối tiếp một lần, vẫn lỗi thì ném (lượt đó tính là lỗi, có nút
///   thử lại). Chỉ đổi model / đổi công tắc lưu lịch sử mới được mở chat mới, và luôn log ❌ kèm lý do.
/// - Đi đường này: chat trong Reader, và quét tên riêng nhiều chương khi bật "Lưu chat vào lịch sử Gemini" (1.3.524 —
///   nối tiếp **đúng** cuộc chat của phiên chat app, không mở cuộc chat riêng). "Kiểm tra kết nối" vẫn là chat tạm.
extension GeminiWebClient {
    /// Chờ trước khi thử lại lượt nối tiếp của quét tên riêng bị từ chối: Google có thể vẫn đang sinh nốt lượt trước
    /// mà app đã cắt (trần tuyệt đối) nên từ chối lượt kế.
    private static let scanContinuationRetryDelay: UInt64 = 5_000_000_000

    /// `persist == false`: chỉ giữ trạng thái trong RAM, không ghi `GeminiWebConversationStore` (từ 1.3.524 không còn
    /// caller nào — quét tên riêng ghi chung trạng thái với chat của phiên).
    /// `forceContext == true`: lượt nối tiếp luôn kèm khối ngữ cảnh hệ thống dù băm không đổi. Quét tên riêng cần cờ
    /// này: prompt trích xuất giống hệt giữa các lượt nên so băm sẽ bỏ nó từ lượt 2, Gemini chỉ nhận raw (lỗi thật).
    /// Cờ này cũng đánh dấu lượt quét tên riêng cho luật "không mở chat mới" (1.3.527).
    /// `idleTimeout` (1.3.526) / `absoluteTimeout` (1.3.527): `nil` = mặc định của controller (45 s / 240 s). Lượt quét
    /// tên riêng gửi ~40.000 ký tự nên cần chờ lâu hơn (log thật: Gemini gửi gói đầu rồi im > 45 s; stream chậm chạm
    /// trần 240 s).
    public func sendConversationStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        persist: Bool = true,
        forceContext: Bool = false,
        idleTimeout: TimeInterval? = nil,
        absoluteTimeout: TimeInterval? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let modelName = config.selectedModel
        let timeouts = (
            idle: idleTimeout ?? GeminiWebSessionController.defaultIdleTimeout,
            absolute: absoluteTimeout ?? GeminiWebSessionController.defaultAbsoluteTimeout
        )
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: GeminiWebError.sessionUnavailable)
                    return
                }
                do {
                    try await self.runConversationTurn(
                        messages: messages,
                        modelName: modelName,
                        sessionId: sessionId,
                        persist: persist,
                        forceContext: forceContext,
                        timeouts: timeouts
                    ) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Một lượt nối tiếp, gom thành chuỗi (quét tên riêng dùng, không cần stream).
    public func sendConversation(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        persist: Bool,
        forceContext: Bool = false,
        idleTimeout: TimeInterval? = nil,
        absoluteTimeout: TimeInterval? = nil
    ) async throws -> String {
        var text = ""
        for try await delta in sendConversationStreaming(
            config: config,
            messages: messages,
            sessionId: sessionId,
            persist: persist,
            forceContext: forceContext,
            idleTimeout: idleTimeout,
            absoluteTimeout: absoluteTimeout
        ) {
            text += delta
        }
        return text
    }

    /// 6 ký tự đầu cid của cuộc chat Gemini gắn với phiên (RAM trước, rồi bản lưu) — chỉ dùng cho log chẩn đoán (1.3.527).
    func conversationCidPrefix(sessionId: UUID) -> String? {
        let cid = (conversations[sessionId] ?? GeminiWebConversationStore.load(sessionId: sessionId))?.cid ?? ""
        return cid.isEmpty ? nil : String(cid.prefix(6))
    }

    private func runConversationTurn(
        messages: [OpenAIChatRequest.Message],
        modelName: String,
        sessionId: UUID,
        persist: Bool,
        forceContext: Bool,
        timeouts: (idle: TimeInterval, absolute: TimeInterval),
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let saveToHistory = GeminiWebConversationStore.saveToHistory
        let systemText = messages.filter { $0.role == "system" }.compactMap(\.content).joined(separator: "\n\n")
        let fingerprint = Chapter.hashUrl(systemText)
        let previous = conversations[sessionId] ?? (persist ? GeminiWebConversationStore.load(sessionId: sessionId) : nil)
        let blocker = Self.continuationBlocker(previous: previous, modelName: modelName, saveToHistory: saveToHistory)
        var freshReason = blocker ?? ""

        if blocker == nil, let previous {
            // Băm vẫn cập nhật theo system của lượt này ⇒ chat thường kế tiếp sau lượt quét thấy lệch và tự gửi lại
            // ngữ cảnh chương.
            let contextUpdate = (forceContext || previous.contextFingerprint != fingerprint) ? systemText : nil
            let prompt = GeminiWebPromptFormatter.buildContinuationPrompt(from: messages, contextUpdate: contextUpdate)
            let attempt = ContinuationAttempt(
                previous: previous,
                prompt: prompt,
                modelName: modelName,
                fingerprint: fingerprint,
                sessionId: sessionId,
                persist: persist,
                saveToHistory: saveToHistory,
                timeouts: timeouts
            )
            guard let rejection = try await continueConversation(attempt, onDelta: onDelta) else {
                AppLogger.shared.log("🤖 [GeminiWeb] Nối tiếp cuộc chat (lưu=\(saveToHistory), cập nhật ngữ cảnh=\(contextUpdate != nil))")
                return
            }
            if forceContext {
                try await retryRejectedScanContinuation(attempt, rejection: rejection, onDelta: onDelta)
                return
            }
            freshReason = "bị Google từ chối: \(rejection.localizedDescription)"
            AppLogger.shared.log("🤖 [GeminiWeb] Cuộc chat cũ bị từ chối (\(rejection.localizedDescription)) — mở cuộc chat mới với đủ ngữ cảnh")
        }

        if forceContext, previous != nil {
            // Phiên đã có trạng thái chat mà lượt quét vẫn phải mở chat mới (đổi model / đổi công tắc / mất cid): đây
            // chính là triệu chứng "mỗi batch một cuộc chat" ⇒ luôn ghi log dù người dùng tắt log.
            AppLogger.shared.log("❌ 🤖 [GeminiWeb] Quét tên riêng mở cuộc chat Gemini MỚI dù phiên đã có chat — lý do: \(freshReason)")
        }

        var state = GeminiWebConversationState(model: modelName, contextFingerprint: fingerprint, savedToHistory: saveToHistory)
        let observed = TurnObservation()
        do {
            state.metadata = try await streamGeneration(
                prompt: GeminiWebPromptFormatter.buildPrompt(from: messages),
                modelName: modelName,
                metadata: GeminiWebConversationState.emptyMetadata,
                temporary: !saveToHistory,
                idleTimeout: timeouts.idle,
                absoluteTimeout: timeouts.absolute,
                onDelta: onDelta,
                onMetadata: { observed.record($0) }
            )
        } catch {
            rememberPartial(state, observed: observed, sessionId: sessionId, persist: persist, error: error)
            var probe = state
            if let partial = observed.metadata { probe.metadata = partial }
            if forceContext, !Task.isCancelled, probe.cid.isEmpty {
                AppLogger.shared.log("❌ 🤖 [GeminiWeb] Quét tên riêng: lượt mở cuộc chat mới lỗi trước khi nhận cid (\(error.localizedDescription)) — Gemini có thể đã tạo cuộc chat trên web, lượt sau sẽ lại mở chat mới")
            }
            throw error
        }
        state.updatedAt = Date()
        remember(state, sessionId: sessionId, persist: persist)
        AppLogger.shared.log("🤖 [GeminiWeb] Mở cuộc chat mới (lưu=\(saveToHistory), có cid=\(!state.cid.isEmpty), lý do: \(freshReason))")
        if state.cid.isEmpty {
            AppLogger.shared.log("❌ 🤖 [GeminiWeb] Mở cuộc chat mới nhưng không lấy được cid — lượt sau sẽ lại mở chat mới")
        }
    }

    /// Lý do **không** nối tiếp được cuộc chat cũ (`nil` = nối tiếp được) — điều kiện y hệt trước 1.3.527, chỉ thêm
    /// chữ cho log chẩn đoán.
    private static func continuationBlocker(
        previous: GeminiWebConversationState?,
        modelName: String,
        saveToHistory: Bool
    ) -> String? {
        guard let previous else { return "chưa có cuộc chat của phiên" }
        if previous.cid.isEmpty { return "trạng thái cũ không có cid" }
        if previous.model != modelName { return "đổi model \(previous.model) → \(modelName)" }
        if previous.savedToHistory != saveToHistory { return "đổi công tắc lưu lịch sử" }
        return nil
    }

    /// Một lần gửi nối tiếp cuộc chat cũ. Thành công ⇒ ghi nhớ trạng thái mới, trả `nil`. Bị Google từ chối **trước khi
    /// có chữ nào** với lỗi có thể do chính cuộc chat cũ (`allowsFreshRestart`) ⇒ trả lỗi đó để caller quyết định (chat
    /// thường mở chat mới; quét tên riêng thử lại nối tiếp). Lỗi khác ⇒ giữ cid đã nhận (`rememberPartial`) rồi ném.
    private func continueConversation(
        _ attempt: ContinuationAttempt,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws -> GeminiWebError? {
        let observed = TurnObservation()
        var state = attempt.previous
        state.contextFingerprint = attempt.fingerprint
        do {
            state.metadata = try await streamGeneration(
                prompt: attempt.prompt,
                modelName: attempt.modelName,
                metadata: attempt.previous.metadata,
                temporary: !attempt.saveToHistory,
                idleTimeout: attempt.timeouts.idle,
                absoluteTimeout: attempt.timeouts.absolute,
                onDelta: { delta in
                    observed.markEmitted()
                    onDelta(delta)
                },
                onMetadata: { observed.record($0) }
            )
        } catch let error as GeminiWebError where !observed.emitted && Self.allowsFreshRestart(after: error) {
            return error
        } catch {
            rememberPartial(state, observed: observed, sessionId: attempt.sessionId, persist: attempt.persist, error: error)
            throw error
        }
        state.updatedAt = Date()
        remember(state, sessionId: attempt.sessionId, persist: attempt.persist)
        return nil
    }

    /// Lượt quét tên riêng bị từ chối khi nối tiếp (1.3.527): **không** mở chat mới — chờ 5 s (huỷ được), thử lại đúng
    /// lượt nối tiếp này một lần; vẫn lỗi thì ném để vòng quét đếm là lượt lỗi (nút "Thử lại" lo phần còn lại).
    private func retryRejectedScanContinuation(
        _ attempt: ContinuationAttempt,
        rejection: GeminiWebError,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        AppLogger.shared.log("❌ 🤖 [GeminiWeb] Quét tên riêng: lượt nối tiếp bị Google từ chối (\(rejection.localizedDescription)) — chờ 5 s rồi thử lại đúng cuộc chat cũ, không mở chat mới")
        try await Task.sleep(nanoseconds: Self.scanContinuationRetryDelay)
        do {
            if let again = try await continueConversation(attempt, onDelta: onDelta) {
                throw again
            }
        } catch {
            if !Task.isCancelled {
                AppLogger.shared.log("❌ 🤖 [GeminiWeb] Quét tên riêng: thử lại nối tiếp vẫn lỗi (\(error.localizedDescription)) — bỏ lượt này, giữ cuộc chat cũ, không mở chat mới")
            }
            throw error
        }
        AppLogger.shared.log("🤖 [GeminiWeb] Quét tên riêng: thử lại nối tiếp thành công, vẫn đúng cuộc chat cũ")
    }

    /// Lượt lỗi giữa chừng (timeout, huỷ…) mà Google **đã** gửi cid: cuộc chat đã có trên web ⇒ giữ nó cho phiên để lượt
    /// sau nối tiếp. Không giữ thì lượt sau mở cuộc chat mới — lỗi thật 1.3.524: quét tên riêng timeout từng lượt ⇒ mỗi
    /// batch một cuộc chat trên Gemini.
    private func rememberPartial(
        _ state: GeminiWebConversationState,
        observed: TurnObservation,
        sessionId: UUID,
        persist: Bool,
        error: Error
    ) {
        guard let partial = observed.metadata else { return }
        var kept = state
        kept.metadata = partial
        guard !kept.cid.isEmpty else { return }
        kept.updatedAt = Date()
        remember(kept, sessionId: sessionId, persist: persist)
        AppLogger.shared.log("🤖 [GeminiWeb] Lượt lỗi (\(error.localizedDescription)) nhưng đã có cid — giữ cuộc chat cho lượt sau nối tiếp")
    }

    private func remember(_ state: GeminiWebConversationState, sessionId: UUID, persist: Bool) {
        conversations[sessionId] = state
        if persist {
            GeminiWebConversationStore.save(state, sessionId: sessionId)
        }
    }

    /// Lỗi của tài khoản/mạng thì mở cuộc chat mới cũng vô ích (và tốn hạn mức) — chỉ thử lại khi lỗi có thể do
    /// chính cuộc chat cũ.
    private static func allowsFreshRestart(after error: GeminiWebError) -> Bool {
        switch error {
        case .usageLimit, .ipBlocked, .notSignedIn, .accountStatus, .timeout, .sessionUnavailable:
            return false
        default:
            return true
        }
    }

    /// Đầu vào của một lần gửi nối tiếp — gom lại để lần thử lại của quét tên riêng gửi **y hệt** lần đầu.
    private struct ContinuationAttempt {
        let previous: GeminiWebConversationState
        let prompt: String
        let modelName: String
        let fingerprint: String
        let sessionId: UUID
        let persist: Bool
        let saveToHistory: Bool
        let timeouts: (idle: TimeInterval, absolute: TimeInterval)
    }
}

/// Quan sát một lượt, dùng chung giữa closure `@Sendable` và actor:
/// - đã phát ít nhất một delta chưa — đã hiện chữ thì không mở lại cuộc chat mới (tránh trả lời trùng);
/// - metadata mới nhất Google gửi về (1.3.526) — để lượt lỗi giữa chừng vẫn giữ được cid.
private final class TurnObservation: @unchecked Sendable {
    private let lock = NSLock()
    private var didEmit = false
    private var latestMetadata: [String?]?

    var emitted: Bool {
        lock.lock(); defer { lock.unlock() }
        return didEmit
    }

    var metadata: [String?]? {
        lock.lock(); defer { lock.unlock() }
        return latestMetadata
    }

    func markEmitted() {
        lock.lock(); didEmit = true; lock.unlock()
    }

    func record(_ metadata: [String?]) {
        lock.lock(); latestMetadata = metadata; lock.unlock()
    }
}
