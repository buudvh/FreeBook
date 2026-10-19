import Foundation

/// Luật dịch tên/mô tả truyện ở các danh sách truyện đã lưu (Kệ sách, Lịch sử, Bộ sưu tập, Tìm trên kệ, sheet chọn
/// truyện): theo **công tắc dịch toàn app** (`@AppStorage("isTranslationEnabled")`, View tự đọc rồi truyền vào) và
/// chỉ dịch khi chuỗi có chữ Hán.
///
/// Một nguồn cho cả `BookListItemView` (hàng danh sách) và `ShelfBookGridCardView` (thẻ lưới) — đổi luật ở đây là
/// đổi cả hai kiểu hiển thị, không để hai bản chép lệch nhau.
enum BookDisplayTranslation {
    static func translateIfNeeded(_ text: String, bookId: String? = nil, isEnabled: Bool) -> String {
        guard isEnabled && TranslateUtils.containsChinese(text) else {
            return text
        }
        return TranslateUtils.translateMeta(text, bookId: bookId)
    }

    /// Tên truyện hiển thị: dịch (nếu cần) rồi viết hoa chữ đầu mỗi từ — đúng thứ tự `BookListItemView` đang làm.
    static func title(_ title: String, bookId: String, isEnabled: Bool) -> String {
        DisplayTextFormatter.titleCase(translateIfNeeded(title, bookId: bookId, isEnabled: isEnabled))
    }
}
