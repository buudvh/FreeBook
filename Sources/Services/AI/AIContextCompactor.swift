import Foundation

/// Dịch vụ tự động thu gọn (compaction) ngữ cảnh phiên chat AI khi vượt quá ngưỡng.
public final class AIContextCompactor: Sendable {
    public static let shared = AIContextCompactor()

    /// Ngưỡng số lượng tin nhắn kích hoạt tự động compact.
    public static let compactionThreshold = 12

    /// Số lượng tin nhắn gần nhất được giữ nguyên vẹn trong cửa sổ trực tiếp.
    public static let recentMessagesPreservedCount = 6

    private init() {}

    /// Kiểm tra và thực hiện compact các tin nhắn cũ nếu session vượt quá ngưỡng.
    /// Trả về bản tóm tắt mới nếu compact thành công, hoặc giữ nguyên tóm tắt cũ.
    public func compactSessionIfNeeded(
        session: AIChatSession,
        config: AIConfiguration
    ) async -> String? {
        guard session.messages.count > Self.compactionThreshold else {
            return session.contextSummary
        }

        let cutoffIndex = session.messages.count - Self.recentMessagesPreservedCount
        guard cutoffIndex > 0 else { return session.contextSummary }

        let olderMessages = Array(session.messages[0..<cutoffIndex])
        var conversationText = ""
        if let existing = session.contextSummary, !existing.isEmpty {
            conversationText += "[Tóm tắt ngữ cảnh trước đó: \(existing)]\n\n"
        }

        for msg in olderMessages {
            let roleName = msg.role == .user ? "Người dùng" : "AI"
            let snippet = msg.content.prefix(500)
            conversationText += "\(roleName): \(snippet)\n"
        }

        let prompt = """
        Hãy đọc đoạn hội thoại sau và tóm tắt súc tích các thông tin then chốt (nhân vật, bối cảnh, câu hỏi chính, kết luận thảo luận) dưới 250 từ để làm ngữ cảnh hội thoại tiếp nối:

        \(conversationText)
        """

        let messages = [
            OpenAIChatRequest.Message(
                role: "system",
                content: "Bạn là chuyên gia tóm tắt ngữ cảnh hội thoại. Chỉ trả về một đoạn văn tóm tắt ngắn gọn, không rườm rà."
            ),
            OpenAIChatRequest.Message(role: "user", content: prompt)
        ]

        do {
            let summary: String?
            if config.activeProfile.apiFormat == "anthropic" {
                let (res, _) = try await AnthropicClient.shared.sendChat(config: config, messages: messages)
                summary = res
            } else {
                let (res, _) = try await OpenAIClient.shared.sendChat(config: config, messages: messages)
                summary = res
            }
            guard let summary else { return session.contextSummary }
            let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? session.contextSummary : trimmed
        } catch {
            AppLogger.shared.log("Lỗi tự động compact ngữ cảnh AI session: \(error.localizedDescription)")
            return session.contextSummary
        }
    }
}
