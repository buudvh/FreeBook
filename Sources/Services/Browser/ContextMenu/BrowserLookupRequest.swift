import Foundation

/// Yêu cầu mở sheet Tra từ điển của trình duyệt.
///
/// - `context`: đoạn chữ chứa từ cần tra (khối chứa vùng chọn, hoặc bản gốc của đoạn đã dịch / vùng chọn của sheet
///   Dịch QT). Sheet tự cắt ra **câu** chứa từ (`TranslateUtils.getSentenceRanges`).
/// - `word`: từ cần tra; rỗng ⇒ tra token có chữ Hán đầu tiên của câu có chữ Hán đầu tiên.
/// - `wordOffset`: vị trí UTF-16 của `word` trong `context` (cùng đơn vị với `NSRange` và chỉ số chuỗi JS); `nil` ⇒
///   tìm lần xuất hiện đầu tiên.
struct BrowserLookupRequest: Identifiable, Sendable {
    let id = UUID()
    let context: String
    let word: String
    let wordOffset: Int?

    init(context: String, word: String = "", wordOffset: Int? = nil) {
        self.context = context
        self.word = word
        self.wordOffset = wordOffset
    }
}
