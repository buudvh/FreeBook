import Foundation

/// Một dòng lời bài hát đã đọc (`AudioLyricParser`).
///
/// `time` = giây bắt đầu hiện dòng (LRC đã cộng `[offset:]`, VTT/SRT = mốc bắt đầu của cue); `nil` = lời không có mốc giờ
/// (chữ thường). `text` rỗng = dòng trống (khoảng nghỉ nhạc của LRC, ngăn đoạn của lời chữ thường).
public struct AudioLyricLine: Sendable, Hashable {
    public let time: Double?
    public let text: String

    public init(time: Double?, text: String) {
        self.time = time
        self.text = text
    }
}
