import Foundation

/// Ghép `[OpenAIChatRequest.Message]` thành **một** prompt cho Gemini Web.
///
/// Gemini Web không có vai trò `system`, và app không giữ cid/rid của hội thoại web — mỗi lượt là
/// một temporary chat mới (`GeminiWebRequestBuilder`, ô `[45]`). System prompt cùng cửa sổ 6 tin gần
/// nhất mà `ReaderAIFullScreenView+Actions.sendUserMessage` đã chọn vì vậy được viết lại thành văn
/// bản có nhãn; model được dặn chỉ trả lời lượt cuối.
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
}
