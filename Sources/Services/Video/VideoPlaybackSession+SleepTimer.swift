import Foundation

/// Hẹn giờ tắt của trình phát phim (`sleepTimer`, `MediaSleepTimer`):
/// - Đếm: `refreshIdleTimer()` (`+Lifecycle`, chạy ở mọi lần trạng thái phát đổi) gọi `syncSleepTimerCounting()` — chỉ đếm
///   khi phim **native** đang phát, ở màn xem, cửa sổ nhỏ, hub hay khi app ở nền (rời app chỉ phát tiếng). Trang nhúng
///   không có trạng thái `AVPlayer` ⇒ không đếm (UI ẩn mục hẹn giờ khi nhúng trang và chưa hẹn).
/// - Hết giờ ⇒ `pause()` của phiên (xoá `keepPlayingDeadline` để lối "thu nhỏ thì phát tiếp" không bật lại phim); màn
///   khoá cập nhật qua đường KVO sẵn có.
/// - "Hết tập" ⇒ `handlePlayedToEnd` (`+Playback`) dừng ở cuối tập: không sang tập kế, không sang phim đề xuất
///   (`VideoAutoNextCoordinator`).
/// - `stop()` ⇒ `reset()`, trừ lượt tự sang phim đề xuất (`open(keepsSleepTimer: true)` giữ lại).
extension VideoPlaybackSession {
    func installSleepTimer() {
        sleepTimer.onExpire = { [weak self] in
            self?.pauseForSleepTimer()
        }
    }

    func syncSleepTimerCounting() {
        sleepTimer.updatePlaybackState(isPlaying: launch != nil && isPlaying && embedContent == nil)
    }

    private func pauseForSleepTimer() {
        guard let launch else { return }
        AppLogger.shared.log("⏱️ [VideoPlayer] Hết giờ hẹn ⇒ tạm dừng phim (bookId=\(launch.bookId))")
        if embedContent != nil {
            // Media của trang nhúng không điều khiển được từ native ⇒ nhờ WKWebView đang hiện dừng (như `pauseForTTS`).
            embedPauseRequest += 1
            return
        }
        pause()
    }

    /// `true` ⇒ hẹn "Hết tập": lưu tập này ở giây 0 (như hết tập cuối — mở lại xem lại tập vừa ngủ quên) và dừng ở đây.
    func stopAtEndOfEpisodeForSleepTimer() -> Bool {
        guard sleepTimer.stopsAfterItemEnded() else { return false }
        AppLogger.shared.log("⏱️ [VideoPlayer] Hẹn giờ hết tập ⇒ dừng ở cuối tập \(currentEpisodeIndex), không sang tập kế / phim đề xuất")
        saveProgress(reason: "hẹn giờ hết tập", seconds: 0)
        publishNowPlaying()
        return true
    }
}
