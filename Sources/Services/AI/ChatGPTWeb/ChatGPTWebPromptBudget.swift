import Foundation

/// Ghép prompt cho ChatGPT Web rồi **cắt cho vừa** ngân sách độ dài của app (1.3.971).
///
/// Ô nhập của trang ẩn danh không có `maxlength`; thử thật một prompt 12.166 ký tự (chữ Hán) gửi và trả lời được. Trần
/// thật của ChatGPT chưa biết ⇒ app tự đặt `maxPromptCharacters` trên mức đã thử một quãng vừa phải; vượt mà ChatGPT báo
/// lỗi thì chỉnh hằng này theo log `🤖 [ChatGPTWeb]`.
///
/// Cắt **đuôi phần ngữ cảnh hệ thống** trước (raw chương nằm cuối system prompt của màn AI); tin của người dùng tự nó vượt
/// ngân sách ⇒ `requestTooLong`. Lượt quét tên riêng không cho cắt (`allowsTrimming == false`): phần hệ thống là chỉ dẫn
/// trích xuất, cắt đi thì kết quả vô nghĩa.
enum ChatGPTWebPromptBudget {
    static let maxPromptCharacters = 20_000

    private static let truncationNote = "\n…(ngữ cảnh đã cắt bớt cho vừa giới hạn độ dài)"

    /// Prompt của một cuộc chat mới — cùng khuôn với Gemini Web (`GeminiWebPromptFormatter.buildPrompt`), gồm cả các tin
    /// gần đây màn AI gửi kèm (ChatGPT ẩn danh không giữ cuộc chat qua lần nạp trang).
    static func freshPrompt(from messages: [OpenAIChatRequest.Message], allowsTrimming: Bool = true) throws -> String {
        let system = systemText(of: messages)
        let others = messages.filter { $0.role != "system" }
        return try fit(context: system, allowsTrimming: allowsTrimming) { context in
            let head = context.isEmpty ? [] : [OpenAIChatRequest.Message(role: "system", content: context)]
            return GeminiWebPromptFormatter.buildPrompt(from: head + others)
        }
    }

    /// Lượt hỏi tiếp trong trang đang mở: tin mới, kèm "Cập nhật ngữ cảnh" khi khối hệ thống đã đổi.
    static func continuationPrompt(from messages: [OpenAIChatRequest.Message], contextUpdate: String?) throws -> String {
        try fit(context: contextUpdate ?? "", allowsTrimming: true) { context in
            GeminiWebPromptFormatter.buildContinuationPrompt(from: messages, contextUpdate: context.isEmpty ? nil : context)
        }
    }

    static func systemText(of messages: [OpenAIChatRequest.Message]) -> String {
        messages.filter { $0.role == "system" }.compactMap(\.content).joined(separator: "\n\n")
    }

    /// Dựng bản đủ; không vừa thì tìm nhị phân phần đầu dài nhất của `context` còn vừa.
    private static func fit(context: String, allowsTrimming: Bool, build: (String) -> String) throws -> String {
        let full = build(context)
        if full.count <= maxPromptCharacters { return full }
        guard allowsTrimming, build("").count <= maxPromptCharacters else {
            AppLogger.shared.log("❌ 🤖 [ChatGPTWeb] Prompt vượt ngân sách độ dài (\(full.count)/\(maxPromptCharacters) ký tự)")
            throw ChatGPTWebError.requestTooLong
        }
        let characters = Array(context)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if build(String(characters[0..<mid]) + truncationNote).count <= maxPromptCharacters {
                low = mid
            } else {
                high = mid - 1
            }
        }
        AppLogger.shared.log("🤖 [ChatGPTWeb] Cắt ngữ cảnh \(characters.count) → \(low) ký tự cho vừa ngân sách độ dài")
        return build(low == 0 ? "" : String(characters[0..<low]) + truncationNote)
    }
}
