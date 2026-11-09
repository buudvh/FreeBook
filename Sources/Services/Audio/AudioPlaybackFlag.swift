import Foundation

/// Trình nghe âm thanh đang phát (player đang chạy hoặc đang chờ đệm giữa lúc phát). Cờ nhẹ để TTS / video hỏi mà không
/// phải chạm `AudioPlaybackSession.shared` (chạm là dựng cả `AVPlayer` nếu trình nghe chưa từng mở) — như
/// `VideoNativePlaybackFlag`.
///
/// Chỉ `AudioPlaybackSession` ghi (`handleTimeControlChange`, `stop`). Người đọc:
/// - `TTSAudioSessionController.deactivateUnlessVideoPlaying`, `VideoPlaybackSession.deactivateAudioSessionIfIdle`: không
///   tắt phiên âm thanh khi nhạc còn phát.
/// - `VideoPlaybackSession.prepareAudioForPlayback`: phim đang tắt tiếng thì phát cùng nhạc, không giành âm thanh.
@MainActor
enum AudioPlaybackFlag {
    private(set) static var isPlaying = false

    static func set(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
    }
}
