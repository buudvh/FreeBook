import Foundation
import AVFoundation

/// Điều khiển phát (phát/dừng, tua, tốc độ, nhấn giữ 2×), Now Playing và nối với màn khoá / PiP.
extension VideoPlaybackSession {
    // MARK: - Phát / dừng

    func play() {
        guard launch != nil else { return }
        autoplayBlockedByTTS = false
        if embedContent != nil {
            requestScreen()
            return
        }
        guard player.currentItem != nil else {
            if case .failed = phase { retry() }
            return
        }
        if reachedEndOfItem || isAtEndOfCurrentItem() {
            seek(to: 0)
        }
        prepareAudioForPlayback()
        player.play()
    }

    func pause() {
        player.pause()
    }

    /// Nút phát/dừng của màn hình, hub và màn khoá. Đang nhúng trang thì không điều khiển được từ ngoài ⇒ mở lại màn.
    func togglePlayPause() {
        if embedContent != nil {
            requestScreen()
            return
        }
        if player.timeControlStatus == .paused {
            play()
        } else {
            pause()
        }
    }

    /// TTS bắt đầu/tiếp tục đọc (`VideoNowPlayingCoordinator.yieldToTTS`) — kể cả khi video chưa giữ phiên (đang nạp
    /// item, đang nhúng trang). Cờ đặt TRƯỚC mọi guard: item nạp xong (`readyToPlay`) không được tự phát dập TTS.
    func pauseForTTS() {
        guard launch != nil else { return }
        autoplayBlockedByTTS = true
        if embedContent != nil {
            // Media của trang nhúng không điều khiển được từ native ⇒ nhờ WKWebView đang hiện dừng hết media của nó.
            // Màn đã thu nhỏ thì WKWebView đã bị huỷ cùng màn, không còn gì phát.
            AppLogger.shared.log("⏸️ [VideoPlayer] TTS bắt đầu phát ⇒ tạm dừng media trang nhúng")
            embedPauseRequest += 1
            return
        }
        guard player.timeControlStatus != .paused else { return }
        AppLogger.shared.log("⏸️ [VideoPlayer] TTS bắt đầu phát ⇒ tạm dừng video")
        player.pause()
    }

    /// Người dùng chủ động chọn phát (mở phim mới, chọn tập, chọn server, thử lại): bỏ cờ nhường TTS và tạm dừng TTS
    /// ngay để item mới tự phát khi sẵn sàng. Tự sang tập kế lúc hết tập **không** đi qua đây — vẫn tôn trọng cờ.
    func beginUserRequestedPlayback() {
        autoplayBlockedByTTS = false
        let tts = TTSManager.shared
        guard tts.isPlaying else { return }
        AppLogger.shared.log("⏸️ [VideoPlayer] Người dùng chọn phát video ⇒ tạm dừng TTS")
        tts.pause()
    }

    // MARK: - Tua

    func seek(by delta: Double) {
        seek(to: currentPlaybackTime + delta)
    }

    /// Kẹp trong `[0, độ dài − 0,5]`. Cập nhật `currentSeconds` ngay để thanh tua không giật lùi chờ tick.
    func seek(to seconds: Double) {
        guard launch != nil, embedContent == nil, let item = player.currentItem else { return }
        var target = max(0, seconds.isFinite ? seconds : 0)
        let duration = item.duration.seconds
        if duration.isFinite, duration > 0 {
            target = min(target, max(0, duration - 0.5))
        }
        currentSeconds = target
        reachedEndOfItem = false
        if skipTargetSeconds != nil { skipTargetSeconds = nil }
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

    static let playbackRates: [Float] = [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2]

    /// `defaultRate` để `play()` (sau tạm dừng, sau `readyToPlay` của tập kế) giữ tốc độ đã chọn.
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        player.defaultRate = rate
        if player.timeControlStatus != .paused, !isBoosting {
            player.rate = rate
        }
        AppLogger.shared.log("⏩ [VideoPlayer] Tốc độ phát: \(rate)×")
        publishNowPlaying()
    }

    /// Nhấn giữ: tạm phát 2×, thả ra thì về tốc độ đã chọn. Không đổi `defaultRate`.
    func setTemporaryBoost(_ active: Bool) {
        guard active != isBoosting else { return }
        // Thả tay luôn được xử lý (kể cả khi item vừa đổi) để không kẹt cờ 2×.
        if active, !hasPlayableItem { return }
        isBoosting = active
        guard player.timeControlStatus != .paused else { return }
        player.rate = active ? 2 : playbackRate
    }

    // MARK: - Now Playing / màn khoá

    func installRemoteActions() {
        VideoNowPlayingCoordinator.shared.actions = VideoNowPlayingCoordinator.Actions(
            play: { [weak self] in self?.play() },
            pause: { [weak self] in self?.pause() },
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            skip: { [weak self] delta in self?.seek(by: delta) },
            nextEpisode: { [weak self] in self?.playNextEpisode() },
            seek: { [weak self] seconds in self?.seek(to: seconds) },
            pauseForTTS: { [weak self] in self?.pauseForTTS() }
        )
    }

    /// Bỏ qua khi video không giữ phiên (coordinator tự kiểm).
    func publishNowPlaying() {
        guard launch != nil, embedContent == nil, player.currentItem != nil else { return }
        let rate = player.timeControlStatus == .playing ? Double(player.rate) : 0
        VideoNowPlayingCoordinator.shared.publish(
            title: currentEpisodeLabel,
            album: bookTitle,
            elapsed: currentPlaybackTime,
            duration: durationSeconds,
            rate: rate,
            defaultRate: Double(playbackRate),
            isPlaying: isPlaying,
            hasNextEpisode: nextEpisode != nil
        )
    }

    // MARK: - PiP

    func installPictureInPicture() {
        guard let coordinator = VideoPictureInPictureCoordinator(playerLayer: layerView.playerLayer) else {
            AppLogger.shared.log("⚠️ [VideoPiP] Máy không hỗ trợ PiP")
            return
        }
        coordinator.onPossibleChange = { [weak self] possible in
            guard let self, self.isPictureInPicturePossible != possible else { return }
            self.isPictureInPicturePossible = possible
        }
        coordinator.onActiveChange = { [weak self] active in
            self?.handlePictureInPictureChange(active: active)
        }
        coordinator.onDidStart = { [weak self] in
            self?.pictureInPictureStartCount += 1
        }
        coordinator.onRestoreRequest = { [weak self] completion in
            self?.restoreFromPictureInPicture(completion: completion)
        }
        pictureInPicture = coordinator
    }

    func togglePictureInPicture() {
        pictureInPicture?.toggle()
    }

    private func handlePictureInPictureChange(active: Bool) {
        if isPictureInPictureActive != active { isPictureInPictureActive = active }
        refreshLayerAttachment()
        if !active { syncMiniPlayerState() }
    }

    /// Khôi phục từ cửa sổ PiP: màn hình còn hiện thì xong ngay; đã thu nhỏ thì mở lại trình phát, xong mới báo AVKit
    /// (layer phải nằm trong cửa sổ để PiP thu về đúng chỗ). `stop()` gỡ `launch` trước khi tắt PiP ⇒ phim vừa đóng
    /// rơi vào guard đầu, không bị mở lại màn.
    private func restoreFromPictureInPicture(completion: @escaping (Bool) -> Void) {
        guard launch != nil else {
            completion(false)
            return
        }
        guard !isScreenAttached else {
            completion(true)
            return
        }
        guard presentScreenHandler != nil else {
            completion(false)
            return
        }
        requestScreen {
            completion(true)
        }
    }
}
