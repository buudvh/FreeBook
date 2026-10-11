import Foundation

/// Khớp từ khoá của ô "Tìm kiếm chương..." trong Reader với tên chương — **trong Swift**, không bằng SQL `LIKE`.
///
/// Vì sao không dùng `LIKE` (1.3.510): SQLite chỉ bỏ qua hoa/thường với ký tự ASCII (gõ "đại đế" không ra
/// "Đại Đế"), không bỏ qua dấu, coi `%`/`_` của người dùng là ký tự đại diện, và chỉ thấy cột lưu trữ (chữ Hán
/// gốc + `title_trans` có thể NULL) chứ không thấy tên đang hiển thị (dịch tại chỗ khi thiếu `title_trans`).
/// So khớp ở đây dùng đúng tuỳ chọn của ô tìm trong chương (`ReaderSearchMatcher`): không phân biệt hoa/thường,
/// không phân biệt dấu và độ rộng ký tự; chuỗi NFC/NFD được Swift coi là bằng nhau.
enum ChapterTitleSearchMatcher {
    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive, .widthInsensitive]

    /// `true` khi `query` (đã trim) xuất hiện trong ít nhất một chuỗi của `candidates`.
    static func matches(_ query: String, anyOf candidates: [String?]) -> Bool {
        guard !query.isEmpty else { return false }
        for case let text? in candidates where !text.isEmpty {
            if text.range(of: query, options: options) != nil { return true }
        }
        return false
    }
}
