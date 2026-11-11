import CoreGraphics
import Foundation

/// Một khối chữ nhận được trên một ảnh truyện tranh, thường là một bong bóng thoại (dịch ảnh, 1.3.826).
///
/// Toạ độ chuẩn hoá 0…1 theo ảnh, gốc **trên-trái** (Vision trả gốc dưới-trái, `ComicTextRecognizer` đã lật). Vì không
/// phụ thuộc bề ngang ảnh đã downsample, cùng một bản lưu dùng được cho mọi cỡ màn.
///
/// Chỉ lưu chữ **gốc**: bản dịch dựng lại mỗi lần hiện (`ComicPageTextTranslator`), nên sửa name là thấy ngay.
struct ComicTextBlock: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    /// Chữ gốc của cả khối — các dòng ghép liền (chữ Hán không có khoảng trắng giữa dòng).
    let text: String
    /// Chiều cao trung bình một dòng, chuẩn hoá theo **chiều cao ảnh** — dùng để chọn cỡ chữ của bản dịch.
    let lineHeight: Double
    /// Nền vùng khối tối (bong bóng đen, khung chữ tối) ⇒ bản dịch vẽ nền đen chữ trắng.
    let isDarkBackground: Bool

    var rect: CGRect {
        CGRect(x: x, y: y, width: width, height: height)
    }
}
