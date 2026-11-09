import Foundation

/// Hẹn giờ tắt của trình nghe (`sleepTimer`, `MediaSleepTimer`):
/// - Đếm: `handleTimeControlChange` (`+Player`) báo trạng thái phát mỗi lần đổi — chỉ đếm khi đang phát, nền vẫn đếm.
/// - Hết giờ ⇒ `pause()` của phiên (bài đang nạp không tự phát), màn khoá cập nhật qua đường KVO sẵn có.
/// - "Hết bài" ⇒ `advanceAfterTrackEnded` (`+Queue`) dừng ở cuối bài, kể cả đang lặp một / lặp album.
/// - `stopSession` (đóng hẳn, mở album khác, TTS giành phiên) ⇒ `reset()`.
extension AudioPlaybackSession {
    func installSleepTimer() {
        sleepTimer.onExpire = { [weak self] in
            self?.pauseForSleepTimer()
        }
    }

    private func pauseForSleepTimer() {
        guard isActive else { return }
        AppLogger.shared.log("⏱️ [AudioPlayer] Hết giờ hẹn ⇒ tạm dừng nhạc (bookId=\(bookId))")
        pause()
        publishNowPlaying()
    }

    /// Như nhánh "hết album" của `advanceAfterTrackEnded`: lưu bài này ở giây 0 (mở lại nghe lại bài vừa ngủ quên), dừng sẵn.
    func stopAtEndOfTrackForSleepTimer() {
        let trackLabel = currentTrackIndex.map { "\($0)" } ?? "?"
        AppLogger.shared.log("⏱️ [AudioPlayer] Hẹn giờ hết bài ⇒ dừng ở cuối bài \(trackLabel), không sang bài kế")
        saveProgress(reason: "hẹn giờ hết bài", seconds: 0)
        shouldAutoplay = false
        phase = .paused
        syncMiniPlayerState()
        publishNowPlaying()
    }
}
