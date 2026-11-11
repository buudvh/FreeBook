import Foundation

/// Một dòng lời bài hát đã đọc (`AudioLyricParser`).
///
/// `time` = giây bắt đầu hiện dòng (LRC đã cộng `[offset:]`, VTT/SRT = mốc bắt đầu của cue); `nil` = lời không có mốc giờ
/// (chữ thường). `text` rỗng = dòng trống (khoảng nghỉ nhạc của LRC, ngăn đoạn của lời chữ thường); `text` luôn là
/// **nguyên văn** sau parse.
/// `converted` = chữ gốc đã chuyển phồn → giản để hiển thị (`MediaCaptionTranslator`, gán sau khi parse; chạy cả khi tắt
/// dịch); `nil` = y như `text`.
/// `translation` = bản dịch VietPhrase để hiển thị (`MediaCaptionTranslator`, gán sau khi parse); `nil` = chưa dịch / không
/// có chữ Hán / cổng dịch tắt.
public struct AudioLyricLine: Sendable, Hashable {
    public let time: Double?
    public let text: String
    public var converted: String?
    public var translation: String?

    public init(time: Double?, text: String, converted: String? = nil, translation: String? = nil) {
        self.time = time
        self.text = text
        self.converted = converted
        self.translation = translation
    }

    /// "Chữ gốc" hiện trên màn (kiểu Gốc, dòng gốc của Song ngữ): chữ đã chuyển phồn → giản nếu có.
    public var displayText: String { converted ?? text }
}
