import Foundation

/// Kết quả `track.js` của tiện ích video, ánh xạ bởi `VideoTrackMapper`.
///
/// `data` giữ **nguyên văn** (với `webview` có thể là URL, HTML, hoặc chuỗi JSON `{"data":…,"host":…}` — nếu
/// script trả object thì đã được `JSON.stringify`). `drm`/`audios`/`danmaku` không được ánh xạ (ngoài phạm vi).
public struct VideoTrack: Sendable, Equatable {
    public let kind: VideoTrackKind
    public let data: String
    public let host: String?
    public let mimeType: String?
    public let headers: [String: String]
    public let timeSkips: [VideoTimeSkip]
    public let subtitles: [VideoSubtitleTrack]

    public init(
        kind: VideoTrackKind,
        data: String,
        host: String? = nil,
        mimeType: String? = nil,
        headers: [String: String] = [:],
        timeSkips: [VideoTimeSkip] = [],
        subtitles: [VideoSubtitleTrack] = []
    ) {
        self.kind = kind
        self.data = data
        self.host = host
        self.mimeType = mimeType
        self.headers = headers
        self.timeSkips = timeSkips
        self.subtitles = subtitles
    }
}
