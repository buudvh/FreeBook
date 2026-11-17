import Foundation

/// Kiểm ô "Từ gốc" của một mục từ điển phiên âm (NghiTTS / VieNeu) lúc nhập — 1.3.975.
///
/// Trước đó sheet chặn **mọi** dấu câu, nên không gõ được `Kamar-Taj`, `S.H.I.E.L.D`, `e-mail`. Nay `-` / `.` được
/// nhận khi kẹp giữa hai chữ / số, theo đúng `TTSReplacementTokenizer` — cùng bộ tách token với lúc đọc
/// (`TTSPhoneticJoinedWords`) và với thay thế từ TTS, nên "ở đây không báo lỗi" là "lúc đọc khớp được".
///
/// Từ gốc không có `-` / `.` cho đúng kết quả cũ: có dấu cách ⇒ lỗi, có dấu câu ⇒ lỗi.
enum TTSPhoneticKeyValidator {
    static let whitespaceMessage = "Từ gốc không được chứa khoảng trắng"
    static let punctuationMessage = "Từ gốc không được chứa dấu câu"
    static let joinerMessage = "Dấu - hoặc . chỉ được nằm giữa hai chữ / số, không dấu cách (Kamar-Taj, S.H.I.E.L.D)"

    /// Câu báo lỗi của `key`, `nil` khi hợp lệ (chuỗi rỗng không tính là lỗi — nút Lưu tự khoá).
    static func error(for key: String) -> String? {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains(" ") { return whitespaceMessage }
        // Dấu câu chỉ còn có thể nằm ở token ký hiệu: `-` / `.` kẹp giữa hai chữ / số đã thuộc token từ.
        for token in TTSReplacementTokenizer.tokens(in: trimmed) where token.kind == .symbol {
            if TTSPhoneticJoinedWords.isJoined(token.text) { return joinerMessage }
            if token.text.rangeOfCharacter(from: .punctuationCharacters) != nil { return punctuationMessage }
        }
        return nil
    }
}
