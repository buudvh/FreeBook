import Foundation

/// Kết quả `track.js` của tiện ích loại `audio` (`ExtensionManager.audioTrack`): nguồn phát (`VideoTrack`, cùng ánh xạ với
/// video — trình nghe chỉ đọc `data`, `headers`, `audios[0]`) + các nguồn lời bài hát.
public struct AudioTrackResult: Sendable, Equatable {
    public let track: VideoTrack
    public let lyrics: [AudioLyricSource]

    public init(track: VideoTrack, lyrics: [AudioLyricSource]) {
        self.track = track
        self.lyrics = lyrics
    }
}
