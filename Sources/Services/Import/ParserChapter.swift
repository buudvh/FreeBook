import Foundation

/// Một chương đã bóc tách từ file người dùng nhập vào (TXT / HTML / EPUB / MOBI / DOCX / FB2).
///
/// Trước 1.3.251 type này khai trong `ShelfView.swift` (tầng View) nên parser ở tầng Services
/// không thể trả về được. Dời xuống đây để chiều phụ thuộc đúng: Views → Services.
///
/// Năm field cuối là **provenance tạm thời** do `ChapterLengthLimiter` ghi khi một chương quá dài
/// bị tách thành nhiều phần. Chúng chỉ sống đến khi sheet xác nhận đóng lại: `performImport` chỉ đọc
/// `title` + `content`, không lưu provenance vào CSDL. Nhờ có `partIndex` nên không bao giờ phải
/// suy ngược từ hậu tố `" (2)"` trong tiêu đề — hậu tố là kết quả, không phải nguồn dữ liệu.
struct ParserChapter: Sendable {
    let title: String
    var content: String
    /// Tiêu đề của chương gốc trước khi bị tách; `nil` khi chương không bị tách.
    var originalTitle: String? = nil
    /// Thứ tự (1-based) của chương gốc trong danh sách trước khi tách.
    var sourceOrdinal: Int? = nil
    /// Phần thứ mấy (1-based) và tổng số phần của chương gốc.
    var partIndex: Int? = nil
    var partCount: Int? = nil
    /// Lý do tách, để hiện trên sheet xác nhận và ghi log.
    var splitReason: String? = nil
}
