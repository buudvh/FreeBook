import Foundation
import AVFoundation

/// Điều khiển phát của trình nghe: phát / dừng, tua, tốc độ, và hành động gắn cho màn khoá (`AudioNowPlayingCoordinator`).
extension AudioPlaybackSession {
    // MARK: - Phát / dừng

    /// Phát (nút, đĩa góc dưới, màn khoá). Đang lỗi ⇒ thử lại; bài đang nạp ⇒ tự phát khi sẵn sàng; đã hết bài ⇒ về đầu.
    func play() {
        guard isActive else { return }
        shouldAutoplay = true
        // Bài lỗi (kể cả lỗi giữa chừng: item hỏng vẫn còn gắn) ⇒ thử lại — `retry` gỡ item hỏng, nạp lại ở giây đang nghe.
        if case .failed = phase {
            retry()
            return
        }
        guard let item = player.currentItem else {
            beginUserRequestedPlayback()
            return
        }
        guard item.status == .readyToPlay else {
            // Item đang đệm ⇒ `readyToPlay` tự phát.
            beginUserRequestedPlayback()
            return
        }
        autoplayBlockedByOtherMedia = false
        if reachedEndOfItem || isAtEndOfCurrentItem() {
            seek(to: 0)
        }
        prepareAudioForPlayback()
        player.play()
    }

    /// Dừng do người dùng. Đang nạp bài ⇒ bài sẵn sàng thì không tự phát.
    func pause() {
        shouldAutoplay = false
        if player.timeControlStatus != .paused {
            player.pause()
        } else {
            syncMiniPlayerState()
        }
    }

    func togglePlayPause() {
        let isPending = (phase == .loading || phase == .buffering) && shouldAutoplay
        if isPlaying || isPending {
            pause()
        } else {
            play()
        }
    }

    // MARK: - Tua

    /// Tua tương đối (nút ±15 s, màn khoá).
    func skip(by delta: Double) {
        seek(to: currentPlaybackTime + delta)
    }

    /// Kẹp trong `[0, độ dài − 0,5]`. Cập nhật `currentSeconds` ngay để thanh tua không giật lùi chờ tick.
    func seek(to seconds: Double) {
        guard isActive, let item = player.currentItem else { return }
        var target = max(0, seconds.isFinite ? seconds : 0)
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 {
            target = min(target, max(0, duration - 0.5))
        }
        currentSeconds = target
        reachedEndOfItem = false
        updateCurrentLyricLine(at: target)
        let tolerance = CMTime(seconds: 0.3, preferredTimescale: 600)
        player.seek(
            to: CMTime(seconds: target, preferredTimescale: 600),
            toleranceBefore: tolerance,
            toleranceAfter: tolerance
        ) { [weak self] _ in
            let owner = self
            Task { @MainActor in
                owner?.publishNowPlaying()
            }
        }
    }

    // MARK: - Tốc độ

    /// `0.5…2` (kẹp). `defaultRate` để `play()` (sau tạm dừng, sang bài kế) giữ tốc độ đã chọn.
    func setPlaybackRate(_ rate: Float) {
        let clamped = min(Self.maximumRate, max(Self.minimumRate, rate.isFinite ? rate : 1))
        playbackRate = clamped
        player.defaultRate = clamped
        if player.timeControlStatus != .paused {
            player.rate = clamped
        }
        AppLogger.shared.log("⏩ [AudioPlayer] Tốc độ phát: \(clamped)×")
        publishNowPlaying()
    }

    // MARK: - Màn khoá

    func installRemoteActions() {
        AudioNowPlayingCoordinator.shared.actions = AudioNowPlayingCoordinator.Actions(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            skip: { [weak self] delta in self?.skip(by: delta) },
            nextTrack: { [weak self] in self?.next() },
            previousTrack: { [weak self] in self?.previous() },
            seek: { [weak self] seconds in self?.seek(to: seconds) },
            pauseForOtherMedia: { [weak self] in self?.pauseForOtherMedia() },
            stopForTTS: { [weak self] in self?.stopForTTS() }
        )
    }
}
