import Foundation

/// Ghép prompt cho Chế độ AI của Google rồi **cắt cho vừa** giới hạn độ dài của Google (1.3.609).
///
/// Câu hỏi nằm trong URL: thử thật URL 61.764 ký tự → 200, 71.385 → HTTP 413 (trần ~64 KB); một chữ Hán ≈ 9 byte khi
/// percent-encode. Ô nhập của trang còn `maxlength=8192`. Ngân sách của app:
/// - lượt điều hướng mới (lượt chat đầu, mọi lượt quét, kiểm tra kết nối): `q` sau mã hoá ≤ `maxEncodedBytes`;
/// - lượt gửi qua ô nhập (chat nối tiếp, kể cả "Cập nhật ngữ cảnh"): thêm điều kiện ≤ `maxComposerCharacters` ký tự.
///
/// Cắt **đuôi phần ngữ cảnh hệ thống** trước (raw chương nằm cuối system prompt của màn AI); tin của người dùng tự nó vượt
/// ngân sách ⇒ `requestTooLong`. Lượt quét tên riêng không cho cắt (`allowsTrimming == false`): phần hệ thống là chỉ dẫn
/// trích xuất, cắt đi thì kết quả vô nghĩa — ném `requestTooLong` để dừng lần quét.
enum GoogleAIModePromptBudget {
    static let maxEncodedBytes = 48_000
    static let maxComposerCharacters = 8_000

    private static let truncationNote = "\n…(ngữ cảnh đã cắt bớt cho vừa giới hạn độ dài của Google)"

    /// Prompt của một cuộc chat mới — cùng khuôn với Gemini Web (`GeminiWebPromptFormatter.buildPrompt`).
    static func freshPrompt(from messages: [OpenAIChatRequest.Message], allowsTrimming: Bool = true) throws -> String {
        let system = systemText(of: messages)
        let others = messages.filter { $0.role != "system" }
        return try fit(context: system, composer: false, allowsTrimming: allowsTrimming) { context in
            let head = context.isEmpty ? [] : [OpenAIChatRequest.Message(role: "system", content: context)]
            return GeminiWebPromptFormatter.buildPrompt(from: head + others)
        }
    }

    /// Lượt nối tiếp gửi qua ô nhập: tin mới, kèm "Cập nhật ngữ cảnh" khi khối hệ thống đã đổi.
    static func continuationPrompt(from messages: [OpenAIChatRequest.Message], contextUpdate: String?) throws -> String {
        try fit(context: contextUpdate ?? "", composer: true, allowsTrimming: true) { context in
            GeminiWebPromptFormatter.buildContinuationPrompt(from: messages, contextUpdate: context.isEmpty ? nil : context)
        }
    }

    static func systemText(of messages: [OpenAIChatRequest.Message]) -> String {
        messages.filter { $0.role == "system" }.compactMap(\.content).joined(separator: "\n\n")
    }

    /// Dựng bản đủ; không vừa thì tìm nhị phân phần đầu dài nhất của `context` còn vừa (mỗi bước dựng lại cả prompt —
    /// prompt chỉ vài chục nghìn ký tự, ~15 bước).
    private static func fit(
        context: String,
        composer: Bool,
        allowsTrimming: Bool,
        build: (String) -> String
    ) throws -> String {
        let full = build(context)
        if fits(full, composer: composer) { return full }
        guard allowsTrimming, fits(build(""), composer: composer) else {
            AppLogger.shared.log("❌ 🤖 [AIMode] Prompt vượt giới hạn độ dài (\(full.count) ký tự, \(GoogleAIModePageContract.encodedLength(full)) byte)")
            throw GoogleAIModeError.requestTooLong
        }
        let characters = Array(context)
        var low = 0
        var high = characters.count
        while low < high {
            let mid = (low + high + 1) / 2
            if fits(build(String(characters[0..<mid]) + truncationNote), composer: composer) {
                low = mid
            } else {
                high = mid - 1
            }
        }
        AppLogger.shared.log("🤖 [AIMode] Cắt ngữ cảnh \(characters.count) → \(low) ký tự cho vừa giới hạn độ dài của Google")
        return build(low == 0 ? "" : String(characters[0..<low]) + truncationNote)
    }

    private static func fits(_ prompt: String, composer: Bool) -> Bool {
        if composer, prompt.count > maxComposerCharacters { return false }
        return GoogleAIModePageContract.encodedLength(prompt) <= maxEncodedBytes
    }
}
