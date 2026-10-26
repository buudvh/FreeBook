import Foundation

/// Lượt quét tên riêng Gemini Web **tạm dừng khi app ở nền**, gửi lại khi app mở lại (1.3.602).
///
/// Vòng chờ/gửi lại nằm ở `HiddenWebForegroundRunner` (từ 1.3.609 dùng chung với Chế độ AI của Google — chuyển nguyên
/// văn, hành vi không đổi): chờ app ở trước, huỷ lượt khi app vào nền rồi gửi lại đúng lượt đó (tối đa 3 lần), lỗi tài
/// khoản/hạn mức (`AINameExtractionBatchProcessor.shouldStopBatch`) không bao giờ gửi lại, quá số lần thì ném
/// `GeminiWebError.interruptedInBackground`. Chat thường trong Reader và "Kiểm tra kết nối" không đi đường này.
extension GeminiWebClient {
    /// `sendConversation` cho lượt quét tên riêng (nối tiếp cuộc chat của phiên), tạm dừng khi app ở nền.
    public func sendNameScanConversation(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        persist: Bool,
        forceContext: Bool = false,
        idleTimeout: TimeInterval? = nil,
        absoluteTimeout: TimeInterval? = nil
    ) async throws -> String {
        try await runPausingInBackground {
            try await self.sendConversation(
                config: config,
                messages: messages,
                sessionId: sessionId,
                persist: persist,
                forceContext: forceContext,
                idleTimeout: idleTimeout,
                absoluteTimeout: absoluteTimeout
            )
        }
    }

    /// `sendChat` cho lượt quét tên riêng (chat tạm), tạm dừng khi app ở nền.
    public func sendNameScanChat(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        idleTimeout: TimeInterval? = nil,
        absoluteTimeout: TimeInterval? = nil
    ) async throws -> (content: String?, toolCalls: [OpenAIChatRequest.ToolCall]?) {
        let content = try await runPausingInBackground {
            try await self.sendChat(
                config: config,
                messages: messages,
                idleTimeout: idleTimeout,
                absoluteTimeout: absoluteTimeout
            ).content
        }
        return (content, nil)
    }

    private func runPausingInBackground<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await HiddenWebForegroundRunner.run(
            logTag: "[GeminiWeb]",
            shouldStop: { AINameExtractionBatchProcessor.shouldStopBatch(on: $0) },
            exhaustedError: GeminiWebError.interruptedInBackground,
            operation
        )
    }
}
