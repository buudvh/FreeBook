import Foundation

/// Chat trong Reader **nối tiếp** một cuộc chat Chế độ AI của Google cho mỗi phiên chat của app (1.3.609).
///
/// - Phiên chưa có cuộc chat ⇒ lượt mới với đủ ngữ cảnh (cắt cho vừa giới hạn độ dài — `GoogleAIModePromptBudget`).
/// - Đã có ⇒ mở lại bằng `mstk` mới nhất rồi gửi tin mới qua ô nhập; khối ngữ cảnh hệ thống đổi (sang chương khác, đổi
///   từ điển…) thì kèm "Cập nhật ngữ cảnh".
/// - Không mở lại được (khôi phục không ra lượt nào, không có ô nhập) ⇒ mở cuộc chat mới với đủ ngữ cảnh, log lý do.
/// - `mstk` ghi ngay khi trang để lộ, kể cả khi lượt sau đó lỗi/bị huỷ (bài học "giữ cid lượt dở" của Gemini Web 1.3.526).
/// - Màn AI chỉ gửi [system, tin hiện tại] cho provider này (Google giữ hội thoại) ⇒ đổi một phiên đang dở sang Chế độ
///   AI thì Google không biết các lượt trước của phiên — cùng đánh đổi với Gemini Web 1.3.524.
extension GoogleAIModeClient {
    func runConversation(
        messages: [OpenAIChatRequest.Message],
        sessionId: UUID,
        onDelta: @escaping @Sendable (String) -> Void
    ) async throws {
        let systemText = GoogleAIModePromptBudget.systemText(of: messages)
        let fingerprint = Chapter.hashUrl(systemText)
        let remember: @Sendable (String) -> Void = { mstk in
            GoogleAIModeConversationStore.save(mstk: mstk, contextFingerprint: fingerprint, sessionId: sessionId)
        }

        if let previous = GoogleAIModeConversationStore.load(sessionId: sessionId), !previous.mstk.isEmpty {
            let contextUpdate = previous.contextFingerprint == fingerprint ? nil : systemText
            let text = try GoogleAIModePromptBudget.continuationPrompt(from: messages, contextUpdate: contextUpdate)
            do {
                _ = try await runTurn(
                    .continuation(mstk: previous.mstk, text: text),
                    isScan: false,
                    timeouts: Self.chatTimeouts,
                    onDelta: onDelta,
                    onMstk: remember
                )
                AppLogger.shared.log("🤖 [AIMode] Nối tiếp cuộc chat (cập nhật ngữ cảnh=\(contextUpdate != nil))")
                return
            } catch GoogleAIModeError.threadUnavailable {
                AppLogger.shared.log("🤖 [AIMode] Không mở lại được cuộc chat cũ — mở cuộc chat mới với đủ ngữ cảnh")
            }
        }

        let prompt = try GoogleAIModePromptBudget.freshPrompt(from: messages)
        _ = try await runTurn(.fresh(prompt), isScan: false, timeouts: Self.chatTimeouts, onDelta: onDelta, onMstk: remember)
        AppLogger.shared.log("🤖 [AIMode] Mở cuộc chat mới cho phiên \(sessionId.uuidString.prefix(8))")
    }
}
