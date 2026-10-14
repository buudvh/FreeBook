import Foundation

/// Chat trong Reader **nối tiếp** một cuộc chat Gemini cho mỗi phiên chat của app (1.3.514).
///
/// - Lượt đầu (hoặc khi phải mở cuộc chat mới) gửi đủ ngữ cảnh như trước (`GeminiWebPromptFormatter.buildPrompt`).
/// - Lượt sau chỉ gửi tin mới của người dùng; khối ngữ cảnh hệ thống đổi (sang chương khác, đổi chế độ, đổi từ
///   điển…) thì gửi kèm "Cập nhật ngữ cảnh".
/// - Mở cuộc chat mới khi: chưa có, đổi model (Google trả 1050 nếu đổi giữa chừng), đổi công tắc lưu lịch sử.
/// - Lượt nối tiếp bị Google từ chối trước khi có chữ nào (vd. cuộc chat đã xoá trên web) ⇒ mở lại cuộc chat mới
///   với đủ ngữ cảnh, đúng một lần. Lỗi tài khoản/hạn mức thì không thử lại.
/// - Đi đường này: chat trong Reader, và quét tên riêng nhiều chương khi bật "Lưu chat vào lịch sử Gemini" (1.3.524 —
///   nối tiếp **đúng** cuộc chat của phiên chat app, không mở cuộc chat riêng). "Kiểm tra kết nối" vẫn là chat tạm.
extension GeminiWebClient {
    /// `persist == false`: chỉ giữ trạng thái trong RAM, không ghi `GeminiWebConversationStore` (từ 1.3.524 không còn
    /// caller nào — quét tên riêng ghi chung trạng thái với chat của phiên).
    /// `forceContext == true`: lượt nối tiếp luôn kèm khối ngữ cảnh hệ thống dù băm không đổi. Quét tên riêng cần cờ
    /// này: prompt trích xuất giống hệt giữa các lượt nên so băm sẽ bỏ nó từ lượt 2, Gemini chỉ nhận raw (lỗi thật).
    /// `idleTimeout` (1.3.526): `nil` = mặc định của controller (45 s). Lượt quét tên riêng gửi ~40.000 ký tự nên cần
    /// chờ lâu hơn (log thật: Gemini gửi gói đầu rồi im > 45 s ⇒ mọi lượt timeout).
    public func sendConversationStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        persist: Bool = true,
        forceContext: Bool = false,
        idleTimeout: TimeInterval? = nil
    ) -> AsyncThrowingStream<String, Error> {
        let modelName = config.selectedModel
        let idleTimeout = idleTimeout ?? GeminiWebSessionController.defaultIdleTimeout
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
                        idleTimeout: idleTimeout
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
        idleTimeout: TimeInterval? = nil
    ) async throws -> String {
        var text = ""
        for try await delta in sendConversationStreaming(
            config: config,
            messages: messages,
            sessionId: sessionId,
            persist: persist,
            forceContext: forceContext,
            idleTimeout: idleTimeout
        ) {
            text += delta
        }
        return text
    }

    private func runConversationTurn(
        messages: [OpenAIChatRequest.Message],
        modelName: String,
        sessionId: UUID,
        persist: Bool,
        forceContext: Bool,
        idleTimeout: TimeInterval,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let saveToHistory = GeminiWebConversationStore.saveToHistory
        let systemText = messages.filter { $0.role == "system" }.compactMap(\.content).joined(separator: "\n\n")
        let fingerprint = Chapter.hashUrl(systemText)
        let previous = conversations[sessionId] ?? (persist ? GeminiWebConversationStore.load(sessionId: sessionId) : nil)
        let canContinue = previous.map {
            !$0.cid.isEmpty && $0.model == modelName && $0.savedToHistory == saveToHistory
        } ?? false

        if canContinue, let previous {
            // Băm vẫn cập nhật theo system của lượt này ⇒ chat thường kế tiếp sau lượt quét thấy lệch và tự gửi lại
            // ngữ cảnh chương.
            let contextUpdate = (forceContext || previous.contextFingerprint != fingerprint) ? systemText : nil
            let prompt = GeminiWebPromptFormatter.buildContinuationPrompt(from: messages, contextUpdate: contextUpdate)
            let observed = TurnObservation()
            var state = previous
            state.contextFingerprint = fingerprint
            do {
                state.metadata = try await streamGeneration(
                    prompt: prompt,
                    modelName: modelName,
                    metadata: previous.metadata,
                    temporary: !saveToHistory,
                    idleTimeout: idleTimeout,
                    onDelta: { delta in
                        observed.markEmitted()
                        onDelta(delta)
                    },
                    onMetadata: { observed.record($0) }
                )
                state.updatedAt = Date()
                remember(state, sessionId: sessionId, persist: persist)
                AppLogger.shared.log("🤖 [GeminiWeb] Nối tiếp cuộc chat (lưu=\(saveToHistory), cập nhật ngữ cảnh=\(contextUpdate != nil))")
                return
            } catch let error as GeminiWebError where !observed.emitted && Self.allowsFreshRestart(after: error) {
                AppLogger.shared.log("🤖 [GeminiWeb] Cuộc chat cũ bị từ chối (\(error.localizedDescription)) — mở cuộc chat mới với đủ ngữ cảnh")
            } catch {
                rememberPartial(state, observed: observed, sessionId: sessionId, persist: persist, error: error)
                throw error
            }
        }

        var state = GeminiWebConversationState(model: modelName, contextFingerprint: fingerprint, savedToHistory: saveToHistory)
        let observed = TurnObservation()
        do {
            state.metadata = try await streamGeneration(
                prompt: GeminiWebPromptFormatter.buildPrompt(from: messages),
                modelName: modelName,
                metadata: GeminiWebConversationState.emptyMetadata,
                temporary: !saveToHistory,
                idleTimeout: idleTimeout,
                onDelta: onDelta,
                onMetadata: { observed.record($0) }
            )
        } catch {
            rememberPartial(state, observed: observed, sessionId: sessionId, persist: persist, error: error)
            throw error
        }
        state.updatedAt = Date()
        remember(state, sessionId: sessionId, persist: persist)
        AppLogger.shared.log("🤖 [GeminiWeb] Mở cuộc chat mới (lưu=\(saveToHistory), có cid=\(!state.cid.isEmpty))")
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
