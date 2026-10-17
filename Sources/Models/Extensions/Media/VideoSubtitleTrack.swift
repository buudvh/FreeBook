import Foundation

/// Một phụ đề của track video — từ `subtitles: [{data, type, label, language}]`. Chỉ hỗ trợ VTT/SRT.
///
/// `data` thường là URL của file phụ đề; giữ nguyên văn như `track.js` trả về.
public struct VideoSubtitleTrack: Sendable, Hashable {
    public let data: String
    public let type: String?
    public let label: String?
    public let language: String?

    public init(data: String, type: String? = nil, label: String? = nil, language: String? = nil) {
        self.data = data
        self.type = type
        self.label = label
        self.language = language
    }
}
