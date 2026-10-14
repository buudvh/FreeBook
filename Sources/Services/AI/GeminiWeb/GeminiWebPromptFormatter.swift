import Foundation

/// Ghép `[OpenAIChatRequest.Message]` thành **một** prompt cho Gemini Web.
///
/// Gemini Web không có vai trò `system` nên system prompt và các lượt được viết lại thành văn bản có nhãn; model
/// được dặn chỉ trả lời lượt cuối. Từ 1.3.514 app giữ cid/rid theo phiên chat (`GeminiWebClient+Conversation`):
/// `buildPrompt` chỉ dùng khi mở cuộc chat Gemini mới, lượt nối tiếp dùng `buildContinuationPrompt`.
/// `ReaderAIFullScreenView+Actions.sendUserMessage` gửi kèm cửa sổ 6 tin gần nhất khi tắt "Lưu chat vào lịch sử
/// Gemini"; bật thì chỉ gửi [system, tin hiện tại] (1.3.524) nên mục "Lịch sử trao đổi" trống.
enum GeminiWebPromptFormatter {
    static func buildPrompt(from messages: [OpenAIChatRequest.Message]) -> String {
        var systemParts: [String] = []
        var turns: [(role: String, text: String)] = []

        for message in messages {
            let text = (message.content ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            switch message.role {
            case "system":
                systemParts.append(text)
            case "assistant":
                turns.append((role: "Trợ lý", text: text))
            default:
                turns.append((role: "Người dùng", text: text))
            }
        }

        var sections: [String] = []
        if !systemParts.isEmpty {
            sections.append("### Hướng dẫn hệ thống\n" + systemParts.joined(separator: "\n\n"))
        }

        let history = turns.dropLast()
        if !history.isEmpty {
            let lines = history.map { "\($0.role): \($0.text)" }
            sections.append("### Lịch sử trao đổi\n" + lines.joined(separator: "\n\n"))
        }

        if let last = turns.last {
            sections.append(
                "### Lượt hiện tại\n\(last.role): \(last.text)\n\n"
                + "(Chỉ trả lời lượt hiện tại, giữ đúng vai trò và định dạng theo hướng dẫn hệ thống; không nhắc lại các nhãn ở trên.)"
            )
        }

        return sections.joined(separator: "\n\n")
    }

    /// Lượt **nối tiếp** một cuộc chat Gemini (1.3.514): Gemini đã có lịch sử nên chỉ gửi tin mới của người dùng;
    /// khi khối ngữ cảnh hệ thống đổi (sang chương khác…) thì kèm bản mới, nói rõ là thay cho bản trước.
    static func buildContinuationPrompt(from messages: [OpenAIChatRequest.Message], contextUpdate: String?) -> String {
        let lastUser = messages.last { $0.role != "system" && $0.role != "assistant" }?.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let contextUpdate, !contextUpdate.isEmpty else { return lastUser }
        return "### Cập nhật ngữ cảnh (thay cho hướng dẫn và ngữ cảnh trước đó)\n" + contextUpdate
            + "\n\n### Lượt hiện tại\nNgười dùng: " + lastUser
    }
}
