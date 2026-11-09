import Foundation

/// Ai đang giữ màn khoá / Trung tâm điều khiển (`MPRemoteCommandCenter` + `MPNowPlayingInfoCenter` dùng chung) ngoài TTS.
///
/// Tại một thời điểm chỉ **một** bên giữ: phim (`VideoNowPlayingCoordinator`), trình nghe âm thanh
/// (`AudioNowPlayingCoordinator`) hoặc TTS (không cờ — là bên còn lại). Mọi hàm ghi Now Playing / bật-tắt lệnh của TTS
/// (`TTSManager+NowPlaying`) và handler lệnh của `TTSNowPlayingController` hỏi `isHeldByMedia` rồi bỏ qua khi phim hoặc
/// nhạc đang giữ. Cả hai coordinator đều nhẹ (không dựng `AVPlayer`) nên hỏi lúc nào cũng được.
///
/// Nhạc và TTS còn chặt hơn "một bên giữ màn khoá": **không bao giờ cùng phát** — nhạc bắt đầu phát ⇒ TTS tắt hẳn
/// (`AudioPlaybackSession.prepareAudioForPlayback` / `beginUserRequestedPlayback` ⇒ `TTSManager.stop`); TTS bắt đầu /
/// tiếp tục đọc ⇒ trình nghe dừng hẳn (`AudioNowPlayingCoordinator.yieldToTTS` ⇒ `AudioPlaybackSession.stopForTTS`).
/// Phim vẫn theo luật nhường (tạm dừng, trả phiên) với cả hai.
@MainActor
enum MediaNowPlayingOwnership {
    static var isHeldByMedia: Bool {
        VideoNowPlayingCoordinator.shared.isHoldingSession || AudioNowPlayingCoordinator.shared.isHoldingSession
    }
}
