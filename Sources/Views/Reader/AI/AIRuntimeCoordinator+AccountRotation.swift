import Foundation

/// Chuyển tài khoản Google giữa lượt chat của Reader (1.3.614) — tách khỏi `AIRuntimeCoordinator.swift` (file chính đã
/// dài) theo mẫu `X+Feature.swift`.
///
/// Chat Chế độ AI gắn với **một** cuộc chat bên Google (`mstk`), mà `mstk` thuộc tài khoản ⇒ tráo tài khoản giữa phiên thì
/// phải quên `mstk` của phiên đó để lượt sau mở cuộc chat mới với đủ ngữ cảnh (đúng đường `threadUnavailable` sẵn có).
extension AIRuntimeCoordinator {
    /// Tạo stream cho một lượt chat theo provider của `config` — giữ nguyên thứ tự rẽ nhánh cũ.
    func makeChatStream(
        config: AIConfiguration,
        messages: [OpenAIChatRequest.Message],
        session: AIChatSession
    ) async -> AsyncThrowingStream<String, Error> {
        if config.activeProfile.isGeminiWeb {
            // Nối tiếp một cuộc chat Gemini cho mỗi phiên chat của app (1.3.514).
            return await GeminiWebClient.shared.sendConversationStreaming(
                config: config,
                messages: messages,
                sessionId: session.id
            )
        }
        if config.activeProfile.isGoogleAIMode {
            // Nối tiếp một cuộc chat Chế độ AI của Google cho mỗi phiên chat của app (1.3.609).
            return await GoogleAIModeClient.shared.sendConversationStreaming(
                config: config,
                messages: messages,
                sessionId: session.id
            )
        }
        if config.activeProfile.apiFormat == "anthropic" {
            return await AnthropicClient.shared.sendChatStreaming(config: config, messages: messages)
        }
        return await OpenAIClient.shared.sendChatStreaming(config: config, messages: messages)
    }

    /// Lượt chat Chế độ AI bị Google giới hạn ⇒ tráo sang tài khoản Google kế tiếp. Trả `config` mới để gửi lại lượt đó;
    /// `nil` = không chuyển được (hết tài khoản / tráo hỏng / lỗi không phải giới hạn hạn mức).
    ///
    /// Chỉ gọi khi lượt chưa phát chữ nào — đang có chữ mà tráo thì người dùng thấy câu trả lời bị đứt rồi viết lại.
    func rotateGoogleAccount(
        after error: Error,
        rotation: GoogleAccountRotation,
        session: AIChatSession
    ) async -> AIConfiguration? {
        guard let googleError = error as? GoogleAIModeError,
              rotation.config.activeProfile.isGoogleAIMode,
              rotation.treatsAsRateLimit(googleError) else { return nil }
        let previousProfileId = rotation.config.activeProfileId
        guard let account = rotation.rotateToNextAccount(),
              await GoogleSessionSwitcher.shared.apply(profile: account) else {
            rotation.rollbackSwitch(to: previousProfileId)
            return nil
        }
        // Ghi vào Cài đặt (người dùng chọn): lần chạy sau bắt đầu bằng tài khoản vừa chuyển.
        AISettingsStore.shared.setActiveProfile(id: account.id)
        GoogleAIModeConversationStore.delete(sessionId: session.id)
        await GoogleAIModeTurnQueue.shared.clearRateLimitBlock()
        AppLogger.shared.log("❌ 🤖 [AIMode] Chat bị Google giới hạn (\(googleError.localizedDescription)) — tráo sang tài khoản \(account.name), mở cuộc chat mới")
        return rotation.config
    }
}
