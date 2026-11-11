import Foundation

/// Một dòng lời bài hát đã đọc (`AudioLyricParser`).
///
/// `time` = giây bắt đầu hiện dòng (LRC đã cộng `[offset:]`, VTT/SRT = mốc bắt đầu của cue); `nil` = lời không có mốc giờ
/// (chữ thường). `text` rỗng = dòng trống (khoảng nghỉ nhạc của LRC, ngăn đoạn của lời chữ thường).
/// `translation` = bản dịch VietPhrase để hiển thị (`MediaCaptionTranslator`, gán sau khi parse); `nil` = chưa dịch / không
/// có chữ Hán / cổng dịch tắt.
public struct AudioLyricLine: Sendable, Hashable {
    public let time: Double?
    public let text: String
    public var translation: String?

    public init(time: Double?, text: String, translation: String? = nil) {
        self.time = time
        self.text = text
        self.translation = translation
    }
}
