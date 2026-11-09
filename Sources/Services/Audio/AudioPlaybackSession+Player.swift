import Foundation
import AVFoundation

/// Dựng `AVPlayerItem` từ bài đã phân giải, quan sát item / `timeControlStatus` / tick 0,5 s (thời gian, dòng lời đang
/// hát, lưu tiến độ định kỳ, nạp sẵn bài kế) và chuyển bài khi hết bài (`+Queue`).
extension AudioPlaybackSession {
    // MARK: - Chuẩn bị lượt nạp mới

    /// Huỷ việc của lượt nạp trước, gỡ item cũ, tăng `loadGeneration`. Trả generation mới.
    func prepareForNewLoad(resumeSeconds: Int) -> Int {
        loadTask?.cancel()
        loadTask = nil
        resolver?.cancel()
        resolver = nil
        detachCurrentItem()
        resetLyrics(sources: [], headers: [:])
        currentSeconds = 0
        durationSeconds = 0
        reachedEndOfItem = false
        wasPlaying = false
        pendingResumeSeconds = resumeSeconds > 2 ? resumeSeconds : nil
        lastMiniProgress = -1
        prefetchAttemptedIndex = nil
        loadGeneration += 1
        return loadGeneration
    }

    /// Vị trí cần giữ khi nạp lại cùng bài (thử lại).
    func resumePointForReload() -> Int {
        if player.currentItem != nil {
            let seconds = Int(currentPlaybackTime)
            if seconds > 2 { return seconds }
        }
        return pendingResumeSeconds ?? 0
    }

    /// Đầu phát nằm trong giây cuối của item (độ dài hữu hạn) — lưu lúc này sẽ ghi giây ≈ độ dài bài.
    func isAtEndOfCurrentItem() -> Bool {
        guard let item = player.currentItem else { return false }
        let duration = item.duration.seconds
        let current = item.currentTime().seconds
        guard duration.isFinite, duration > 0, current.isFinite else { return false }
        return current >= duration - 1
    }

    // MARK: - Áp bài đã phân giải

    func apply(prepared: AudioPreparedTrack, generation: Int) {
        guard isCurrentLoad(generation) else { return }
        switch prepared.plan {
        case .native(let url, let headers):
            AppLogger.shared.log("▶️ [AudioPlayer] Phát native \(VideoSourceResolution.redact(url)) headers=\(headers.count) mime=\(prepared.mimeType ?? "-")")
            let options = VideoPlaybackSession.assetOptions(headers: headers, mimeType: prepared.mimeType)
            attach(asset: AVURLAsset(url: url, options: options))
        case .hlsText(let playlist, let baseURL, let headers, let subPlaylists):
            AppLogger.shared.log("▶️ [AudioPlayer] Phát HLS dạng text (\(playlist.utf8.count) byte) base=\(baseURL?.host ?? "-")")
            let made = HLSPlaylistResourceLoader.makeAsset(playlist: playlist, baseURL: baseURL, headers: headers, subPlaylists: subPlaylists)
            hlsLoader = made.loader
            attach(asset: made.asset)
        case .embed:
            AppLogger.shared.log("❌ [AudioPlayer] Bài \(prepared.trackIndex): \(PlaybackError.embedOnly.localizedDescription)")
            fail(generation: generation, message: PlaybackError.embedOnly.localizedDescription)
            return
        }
        resetLyrics(sources: prepared.lyricSources, headers: prepared.lyricHeaders)
    }

    private func attach(asset: AVURLAsset) {
        let item = AVPlayerItem(asset: asset)
        observe(item: item)
        player.replaceCurrentItem(with: item)
        phase = .buffering
        syncMiniPlayerState()
    }

    // MARK: - Quan sát

    func installPlayerObservers() {
        guard timeObserverToken == nil else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            let seconds = time.seconds
            MainActor.assumeIsolated {
                self?.handleTick(seconds: seconds)
            }
        }
        // KVO không chắc giao trên main ⇒ hop qua Task; chụp `self` (weak) vào hằng trước khi đưa vào closure `@Sendable`.
        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] _, _ in
            let owner = self
            Task { @MainActor in
                owner?.handleTimeControlChange()
            }
        }
    }

    private func observe(item: AVPlayerItem) {
        let itemId = ObjectIdentifier(item)
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] _, _ in
            let owner = self
            Task { @MainActor in
                owner?.handleItemStatusChange(itemId: itemId)
            }
        }
        let center = NotificationCenter.default
        let endToken = center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handlePlayedToEnd(itemId: itemId)
            }
        }
        let failToken = center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] note in
            let message = (note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)?.localizedDescription
            MainActor.assumeIsolated {
                self?.handleItemFailure(itemId: itemId, message: message ?? "Mất kết nối khi đang phát")
            }
        }
        itemNotificationTokens = [endToken, failToken]
    }

    func detachCurrentItem() {
        handledReadyItem = nil
        itemStatusObservation?.invalidate()
        itemStatusObservation = nil
        for token in itemNotificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        itemNotificationTokens = []
        if player.currentItem != nil {
            player.replaceCurrentItem(with: nil)
        }
        hlsLoader = nil
    }

    private func isCurrentItem(_ itemId: ObjectIdentifier) -> Bool {
        guard isActive, let item = player.currentItem else { return false }
        return ObjectIdentifier(item) == itemId
    }

    private func handleItemStatusChange(itemId: ObjectIdentifier) {
        guard isCurrentItem(itemId), let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            guard handledReadyItem != itemId else { return }
            handledReadyItem = itemId
            if case .failed = phase { return }
            if let resume = pendingResumeSeconds {
                pendingResumeSeconds = nil
                player.seek(to: CMTime(seconds: Double(resume), preferredTimescale: 600))
                currentSeconds = Double(resume)
                AppLogger.shared.log("⏩ [AudioPlayer] Tua tới giây đã lưu: \(resume)")
            }
            refreshDuration()
            // Lời nạp sau khi bài sẵn sàng — không chặn việc phát.
            loadLyricsIfNeeded()
            guard shouldAutoplay else {
                if player.timeControlStatus != .paused { player.pause() }
                phase = .paused
                AppLogger.shared.log("⏸️ [AudioPlayer] Bài sẵn sàng, dừng sẵn (mở lại lúc khởi động / người dùng đã bấm dừng)")
                syncMiniPlayerState()
                return
            }
            guard !autoplayBlockedByOtherMedia, !TTSManager.shared.isPlaying else {
                // TTS / phim đã giành âm thanh ⇒ chỉ chuẩn bị bài, chờ người dùng bấm phát.
                autoplayBlockedByOtherMedia = true
                if player.timeControlStatus != .paused { player.pause() }
                phase = .paused
                AppLogger.shared.log("⏸️ [AudioPlayer] Bài sẵn sàng nhưng TTS / phim đang giữ âm thanh ⇒ không tự phát")
                syncMiniPlayerState()
                return
            }
            prepareAudioForPlayback()
            // `play()` dùng `defaultRate` ⇒ giữ tốc độ người dùng chọn qua các bài.
            player.play()
            publishNowPlaying()
        case .failed:
            handleItemFailure(itemId: itemId, message: item.error?.localizedDescription ?? "Không rõ lỗi")
        default:
            break
        }
    }

    private func handleItemFailure(itemId: ObjectIdentifier, message: String) {
        guard isCurrentItem(itemId) else { return }
        let trackLabel = currentTrackIndex.map { "\($0)" } ?? "?"
        AppLogger.shared.log("❌ [AudioPlayer] Bài \(trackLabel) phát lỗi: \(message)")
        fail(generation: loadGeneration, message: "Không phát được bài này: \(message)",
             link: currentTrack.flatMap { trackErrorLink(for: nil, track: $0) })
    }

    func handleTimeControlChange() {
        let status = player.timeControlStatus
        let playing = status != .paused
        if isPlaying != playing { isPlaying = playing }
        AudioPlaybackFlag.set(playing && isActive)
        guard isActive, player.currentItem != nil else {
            syncMiniPlayerState()
            return
        }
        switch status {
        case .playing:
            if phase != .playing { phase = .playing }
            if !wasPlaying {
                wasPlaying = true
                reachedEndOfItem = false
                // Phát thật (kể cả nút phát của màn khoá / tai nghe đi thẳng vào `AVPlayer`) ⇒ hết nhường TTS / phim.
                autoplayBlockedByOtherMedia = false
                prepareAudioForPlayback()
                saveProgress(reason: "bắt đầu phát")
            }
        case .waitingToPlayAtSpecifiedRate:
            if phase == .playing || phase == .paused { phase = .buffering }
        case .paused:
            if wasPlaying {
                wasPlaying = false
                lastPauseUptime = ProcessInfo.processInfo.systemUptime
                // KVO `.paused` tới SAU `didPlayToEnd` ⇒ đừng ghi giây ≈ độ dài bài.
                if !reachedEndOfItem { saveProgress(reason: "tạm dừng") }
            }
            if player.currentItem?.status == .readyToPlay, phase == .playing || phase == .buffering {
                phase = .paused
            }
        @unknown default:
            break
        }
        syncMiniPlayerState()
        publishNowPlaying()
    }

    private func handlePlayedToEnd(itemId: ObjectIdentifier) {
        guard isCurrentItem(itemId) else { return }
        reachedEndOfItem = true
        advanceAfterTrackEnded()
    }

    // MARK: - Tick 0,5 giây

    private func handleTick(seconds: Double) {
        guard isActive, player.currentItem != nil, seconds.isFinite else { return }
        if abs(currentSeconds - seconds) >= 0.2 { currentSeconds = max(0, seconds) }
        refreshDuration()
        updateCurrentLyricLine(at: seconds)
        if player.timeControlStatus == .playing {
            if ProcessInfo.processInfo.systemUptime - lastProgressSaveUptime >= 10 {
                saveProgress(reason: "định kỳ")
            }
            prefetchNextIfNeeded()
        }
        syncMiniProgress()
        if AudioNowPlayingCoordinator.shared.needsRepublish() {
            publishNowPlaying()
        }
    }

    func refreshDuration() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        let newDuration = duration.isFinite && duration > 0 ? duration : 0
        if newDuration != durationSeconds { durationSeconds = newDuration }
    }
}
