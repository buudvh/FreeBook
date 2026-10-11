import Foundation

/// Chat trong Reader **nối tiếp** một cuộc chat Gemini cho mỗi phiên chat của app (1.3.514).
///
/// - Lượt đầu (hoặc khi phải mở cuộc chat mới) gửi đủ ngữ cảnh như trước (`GeminiWebPromptFormatter.buildPrompt`).
/// - Lượt sau chỉ gửi tin mới của người dùng; khối ngữ cảnh hệ thống đổi (sang chương khác, đổi chế độ, đổi từ
///   điển…) thì gửi kèm "Cập nhật ngữ cảnh".
/// - Mở cuộc chat mới khi: chưa có, đổi model (Google trả 1050 nếu đổi giữa chừng), đổi công tắc lưu lịch sử.
/// - Lượt nối tiếp bị Google từ chối trước khi có chữ nào (vd. cuộc chat đã xoá trên web) ⇒ mở lại cuộc chat mới
///   với đủ ngữ cảnh, đúng một lần. Lỗi tài khoản/hạn mức thì không thử lại.
/// - Chỉ chat trong Reader đi đường này; quét tên riêng và "Kiểm tra kết nối" vẫn là chat tạm, không nối tiếp.
extension GeminiWebClient {
    public func sendConversationStreaming(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID
    ) -> AsyncThrowingStream<String, Error> {
        let modelName = config.selectedModel
        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: GeminiWebError.sessionUnavailable)
                    return
                }
                do {
                    try await self.runConversationTurn(messages: messages, modelName: modelName, sessionId: sessionId) {
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

    private func runConversationTurn(
        messages: [OpenAIChatRequest.Message],
        modelName: String,
        sessionId: UUID,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let saveToHistory = GeminiWebConversationStore.saveToHistory
        let systemText = messages.filter { $0.role == "system" }.compactMap(\.content).joined(separator: "\n\n")
        let fingerprint = Chapter.hashUrl(systemText)
        let previous = conversations[sessionId] ?? GeminiWebConversationStore.load(sessionId: sessionId)
        let canContinue = previous.map {
            !$0.cid.isEmpty && $0.model == modelName && $0.savedToHistory == saveToHistory
        } ?? false

        if canContinue, let previous {
            let contextUpdate = previous.contextFingerprint == fingerprint ? nil : systemText
            let prompt = GeminiWebPromptFormatter.buildContinuationPrompt(from: messages, contextUpdate: contextUpdate)
            let emitted = DeltaFlag()
            do {
                var state = previous
                state.metadata = try await streamGeneration(
                    prompt: prompt,
                    modelName: modelName,
                    metadata: previous.metadata,
                    temporary: !saveToHistory
                ) { delta in
                    emitted.set()
                    onDelta(delta)
                }
                state.contextFingerprint = fingerprint
                state.updatedAt = Date()
                remember(state, sessionId: sessionId)
                AppLogger.shared.log("🤖 [GeminiWeb] Nối tiếp cuộc chat (lưu=\(saveToHistory), cập nhật ngữ cảnh=\(contextUpdate != nil))")
                return
            } catch let error as GeminiWebError where !emitted.value && Self.allowsFreshRestart(after: error) {
                AppLogger.shared.log("🤖 [GeminiWeb] Cuộc chat cũ bị từ chối (\(error.localizedDescription)) — mở cuộc chat mới với đủ ngữ cảnh")
            }
        }

        var state = GeminiWebConversationState(model: modelName, contextFingerprint: fingerprint, savedToHistory: saveToHistory)
        state.metadata = try await streamGeneration(
            prompt: GeminiWebPromptFormatter.buildPrompt(from: messages),
            modelName: modelName,
            metadata: GeminiWebConversationState.emptyMetadata,
            temporary: !saveToHistory,
            onDelta: onDelta
        )
        state.updatedAt = Date()
        remember(state, sessionId: sessionId)
        AppLogger.shared.log("🤖 [GeminiWeb] Mở cuộc chat mới (lưu=\(saveToHistory), có cid=\(!state.cid.isEmpty))")
    }

    private func remember(_ state: GeminiWebConversationState, sessionId: UUID) {
        conversations[sessionId] = state
        GeminiWebConversationStore.save(state, sessionId: sessionId)
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

/// Cờ "đã phát ít nhất một delta" dùng chung giữa closure `@Sendable` và actor — chỉ để quyết định có được mở lại
/// cuộc chat mới hay không (đã hiện chữ thì không mở lại, tránh trả lời trùng).
private final class DeltaFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    var value: Bool {
        lock.lock(); defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock(); flag = true; lock.unlock()
    }
}
