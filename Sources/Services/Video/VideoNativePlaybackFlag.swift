import Foundation

/// Phim **native** (không nhúng) đang phát — kể cả đang tắt tiếng phát cùng TTS. Cờ nhẹ để tầng TTS hỏi mà không phải
/// chạm `VideoPlaybackSession.shared` (chạm là dựng cả `AVPlayer` nếu phiên chưa từng mở).
///
/// Chỉ `VideoPlaybackSession` ghi (`handleTimeControlChange`, `stop`). `TTSAudioSessionController.deactivateUnlessVideoPlaying`
/// đọc: TTS dừng hẳn mà phim còn phát thì không `setActive(false)` — tắt phiên lúc đó thì KVO `outputVolume` của
/// `VideoVolumeObserver` im luôn (nút âm lượng cứng không hiện thanh, không bỏ tắt tiếng được nữa).
@MainActor
enum VideoNativePlaybackFlag {
    private(set) static var isPlaying = false

    static func set(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
    }
}
