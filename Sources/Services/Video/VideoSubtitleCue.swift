import Foundation

/// Một dòng phụ đề đã parse (SRT/WebVTT): hiện `text` trong khoảng `start..<end` (giây).
public struct VideoSubtitleCue: Sendable, Hashable {
    public let start: TimeInterval
    public let end: TimeInterval
    /// Đã bỏ thẻ định dạng (`<i>`, `<c.x>`, `{\an8}`…) và giải mã entity cơ bản; nhiều dòng nối bằng `\n`.
    public let text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}
