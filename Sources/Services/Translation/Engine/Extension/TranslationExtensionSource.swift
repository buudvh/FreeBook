import Foundation

/// Giá trị tham số `source` của `translate.js` (hợp đồng tiện ích): phần nào của app đang xin dịch.
public enum TranslationExtensionSource: String, Sendable {
    /// Nội dung chương đang đọc.
    case chapterContent
    /// Tên chương / tập.
    case tableOfContent
    /// Chữ ở trang Chi tiết.
    case detail
    /// Chữ ở Khám phá / Thể loại / Tìm kiếm.
    case discovery
    /// Không gắn nhãn (ô Dịch thử).
    case untagged = ""
}
