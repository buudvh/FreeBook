import Foundation

/// Luật **"dấu câu chỉ là chỗ cắt khi theo sau là khoảng trắng"** (1.3.919) — dùng chung cho mọi lớp cắt chữ của TTS:
/// `TTSParagraphBuilder` (mọi engine), `NghiUtteranceSegmenter` (NghiTTS + VieNeu), bộ tách câu trong
/// `VieNeuTTSEngine+Chunking`. Engine Piper (`ONNXPiperEngine.punctuationRegex`) viết cùng luật bằng regex.
///
/// Trước đây mọi dấu "." đều là hết câu (trừ giữa hai chữ số), nên "S.H.I.E.L.D" bị xẻ thành sáu lượt đọc "S." / "H." /
/// … và đọc ngắt sau từng chữ cái. Dấu dính liền chữ phía sau ("S.H.I.E.L.D", "U.S.A", "v1.2", "3.14", "1,5") giờ không
/// phải chỗ cắt; câu thường luôn có khoảng trắng sau dấu nên vẫn cắt và nghỉ như cũ.
enum TTSPunctuationBoundary {
    /// Dấu đóng được đứng ngay sau dấu câu mà vẫn tính là hết câu / vế (`Nói: "Đi."` ⇒ cắt sau `."`).
    static let closingMarks: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}", "»", "」", "』", "】", "］", "）"]
    /// Dấu hết câu đứng liền nhau vẫn là một chỗ cắt (`...`, `?!`): dấu trước tính là ranh giới, lớp gọi tự gộp cả cụm.
    static let runMarks: Set<Character> = [".", "!", "?", "…"]
    /// Dấu câu của chữ CJK — chữ CJK không có dấu cách sau dấu nên luôn là ranh giới.
    static let cjkMarks: Set<Character> = ["。", "！", "？", "，", "；", "：", "、"]

    /// Dấu ở `index` có phải chỗ cắt không: dấu CJK, hoặc theo sau là khoảng trắng / dấu đóng / dấu câu khác / hết chuỗi.
    static func isBoundary(at index: Int, in characters: [Character]) -> Bool {
        if cjkMarks.contains(characters[index]) { return true }
        let next = index + 1
        guard next < characters.count else { return true }
        let following = characters[next]
        return following.isWhitespace || closingMarks.contains(following) || runMarks.contains(following)
    }
}
