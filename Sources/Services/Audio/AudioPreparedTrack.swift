import Foundation

/// Một bài đã phân giải xong (`chap` → `track` → `VideoSourceResolver`) — dùng ngay cho lượt nạp, hoặc giữ làm bản **nạp
/// sẵn** cho bài kế (`AudioPlaybackSession+TrackLoading`). Bản nạp sẵn chỉ dùng được trong cùng lượt mở album
/// (`openGeneration`) và trong `maxAge` (link phát hay có chữ ký hết hạn).
struct AudioPreparedTrack {
    /// Quá thời gian này (giây) thì bỏ bản nạp sẵn, nạp lại từ đầu.
    static let maxAge: TimeInterval = 600

    /// Chỉ số mục lục của bài.
    let trackIndex: Int
    let openGeneration: Int
    /// `.native` / `.hlsText` — `.embed` đã bị loại lúc phân giải (trình nghe không nhúng trang).
    let plan: VideoPlaybackPlan
    let mimeType: String?
    let lyricSources: [AudioLyricSource]
    /// Header của track (`track.headers`) — tải lời bài hát dạng URL.
    let lyricHeaders: [String: String]
    /// `ProcessInfo.systemUptime` lúc phân giải xong.
    let preparedAt: TimeInterval

    func isUsable(openGeneration current: Int, now: TimeInterval) -> Bool {
        openGeneration == current && now - preparedAt <= Self.maxAge
    }

    // MARK: - Track phát được

    /// Track đưa vào resolver theo hợp đồng tiện ích (trình nghe chỉ đọc `data`, `headers`, `audios[0]`):
    /// - `audios[0].data` thay `data`; `audios[0].headers` thay header khi khác rỗng; MIME chỉ lấy `audios[0].type` khi nó
    ///   có dạng MIME (`audio/mp4`), còn lại để AVFoundation tự đoán.
    /// - Bỏ `audios` / phụ đề / `timeSkip` — `VideoSourceResolver` gặp `audios` sẽ ghép tiếng vào hình
    ///   (`VideoAudioRenditionComposer`), trình nghe không cần.
    /// - `auto` / `webview` mà `data` đã là URL file nghe tuyệt đối (`.mp3`, `.m4a`…) ⇒ `native`: bộ dò link của phim chỉ
    ///   nhận đuôi video, để nguyên sẽ mở trang ẩn dò link vô ích.
    static func playableTrack(from track: VideoTrack) -> (track: VideoTrack, mimeType: String?) {
        var data = track.data
        var headers = track.headers
        var mimeType = track.mimeType
        if let first = track.audios.first {
            data = first.data
            if !first.headers.isEmpty { headers = first.headers }
            mimeType = first.type.flatMap { $0.contains("/") ? $0 : nil }
        }
        var kind = track.kind
        if kind != .native, isDirectMediaURL(data) {
            kind = .native
        }
        let playable = VideoTrack(kind: kind, data: data, host: track.host, mimeType: mimeType, headers: headers)
        return (playable, mimeType)
    }

    private static let directMediaExtensions: Set<String> = [
        "mp3", "m4a", "m4b", "aac", "flac", "wav", "ogg", "oga", "opus", "weba", "webm", "mp4", "m3u8"
    ]

    private static func isDirectMediaURL(_ data: String) -> Bool {
        let probe = data.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !probe.contains("\n"), let url = URL(string: probe),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return false }
        return directMediaExtensions.contains(url.pathExtension.lowercased())
    }
}
