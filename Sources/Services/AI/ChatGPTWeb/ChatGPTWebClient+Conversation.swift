import Foundation

/// Chat trong Reader qua ChatGPT Web (1.3.971), trang ẩn danh lẫn trang đã đăng nhập.
///
/// Cuộc chat ẩn danh chỉ sống trong trang đang mở — nạp lại `/uc/<id>` bị đưa về trang chủ (đã thử); đã đăng nhập thì
/// app dùng chat tạm, cũng mất khi nạp lại. Nên:
/// - trang còn giữ cuộc chat của **đúng phiên chat app này** (`ChatGPTWebSessionController.liveSession`: lượt chat trước
///   của phiên thành công, chưa quá thời gian giữ trang, chưa có lượt nào khác điều hướng) ⇒ hỏi tiếp ngay trong trang,
///   chỉ gửi tin mới; khối ngữ cảnh hệ thống đổi (sang chương khác, đổi từ điển…) thì kèm "Cập nhật ngữ cảnh";
/// - không thì mở cuộc chat mới với đủ ngữ cảnh **và các tin gần đây** màn AI gửi kèm (màn AI vẫn gửi cửa sổ 6 tin cho
///   provider này — khác Chế độ AI của Google, ở đây không có gì để khôi phục phía ChatGPT);
/// - lượt hỏi tiếp không dùng được trang (`threadUnavailable`: trang đã về trắng, đang có hộp mời đăng nhập, cổng chặn…)
///   ⇒ rơi xuống mở cuộc chat mới, log lý do.
extension ChatGPTWebClient {
    func runConversation(
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let systemText = ChatGPTWebPromptBudget.systemText(of: messages)
        let live = ChatGPTWebLiveSession(
            sessionId: sessionId,
            contextFingerprint: Chapter.hashUrl(systemText)
        )

        if let previous = await ChatGPTWebSessionController.shared.liveSession, previous.sessionId == sessionId {
            let contextUpdate = previous.contextFingerprint == live.contextFingerprint ? nil : systemText
            let text = try ChatGPTWebPromptBudget.continuationPrompt(from: messages, contextUpdate: contextUpdate)
            do {
                _ = try await runTurn(
                    .continuation(sessionId: sessionId, text: text),
                    isScan: false,
                    timeouts: Self.chatTimeouts,
                    live: live,
                    onDelta: onDelta
                )
                AppLogger.shared.log("🤖 [ChatGPTWeb] Hỏi tiếp trong trang đang mở (cập nhật ngữ cảnh=\(contextUpdate != nil))")
                return
            } catch ChatGPTWebError.threadUnavailable {
                AppLogger.shared.log("🤖 [ChatGPTWeb] Trang không còn dùng được để hỏi tiếp — mở cuộc chat mới với đủ ngữ cảnh")
            }
        }

        let prompt = try ChatGPTWebPromptBudget.freshPrompt(from: messages)
        _ = try await runTurn(.fresh(prompt), isScan: false, timeouts: Self.chatTimeouts, live: live, onDelta: onDelta)
        AppLogger.shared.log("🤖 [ChatGPTWeb] Mở cuộc chat mới cho phiên \(sessionId.uuidString.prefix(8))")
    }
}
