import Foundation

/// Một luồng tiếng riêng của track video — từ `audios: [{data, type, label, language, headers}]` (hoặc trường đơn cũ
/// `audio`). Ca thật: Dailymotion trả `data` của track là playlist con chỉ có hình, tiếng nằm ở đây.
///
/// `data` thường là URL playlist HLS của tiếng; giữ nguyên văn như `track.js` trả về. `headers` là header riêng của
/// luồng tiếng (rỗng ⇒ dùng `track.headers`).
public struct VideoAudioTrack: Sendable, Hashable {
    public let data: String
    public let type: String?
    public let label: String?
    public let language: String?
    public let headers: [String: String]

    public init(
        data: String,
        type: String? = nil,
        label: String? = nil,
        language: String? = nil,
        headers: [String: String] = [:]
    ) {
        self.data = data
        self.type = type
        self.label = label
        self.language = language
        self.headers = headers
    }
}
