import Foundation

/// Một dòng phụ đề đã parse (SRT/WebVTT): hiện `text` trong khoảng `start..<end` (giây).
public struct VideoSubtitleCue: Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval
    /// **Nguyên văn** sau parse — đã bỏ thẻ định dạng (`<i>`, `<c.x>`, `{\an8}`…) và giải mã entity cơ bản; nhiều dòng nối
    /// bằng `\n`. Không bao giờ bị ghi đè bởi bước chuyển / dịch.
    public let text: String
    /// Chữ gốc đã chuyển phồn → giản để hiển thị (`MediaCaptionTranslator`, gán sau khi parse; chạy cả khi tắt dịch);
    /// `nil` = y như `text`. Parser không bao giờ điền trường này.
    public var converted: String?
    /// Bản dịch VietPhrase để hiển thị (`MediaCaptionTranslator`, gán sau khi parse); `nil` = chưa dịch / không có chữ Hán /
    /// cổng dịch tắt. Parser không bao giờ điền trường này.
    public var translation: String?

    public init(start: TimeInterval, end: TimeInterval, text: String, converted: String? = nil, translation: String? = nil) {
        self.start = start
        self.end = end
        self.text = text
        self.converted = converted
        self.translation = translation
    }

    /// "Chữ gốc" hiện trên màn (kiểu Gốc, dòng phụ của Song ngữ): chữ đã chuyển phồn → giản nếu có.
    public var displayText: String { converted ?? text }
}
