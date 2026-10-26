import Foundation
import AVFoundation
import UIKit

/// Vòng đời phiên xem: lưu tiến độ (số giây vào `paragraphIndex`), vào nền / về trước (PiP hoặc chỉ phát tiếng),
/// `AVAudioSession`, nhường TTS và `isIdleTimerDisabled`.
extension VideoPlaybackSession {
    // MARK: - Tiến độ

    /// Ghi qua `ReadingProgressStore.checkpoint` (owner `.reader`) để phim vào tab Lịch sử.
    /// Với video, `paragraphIndex` là **số giây** đã xem.
    func saveProgress(reason: String, seconds overrideSeconds: Int? = nil) {
        guard let launch, let episode = currentEpisode else { return }
        let seconds: Int
        if let overrideSeconds {
            seconds = overrideSeconds
        } else if embedContent != nil {
            seconds = embedProgressSeconds
        } else if let pending = pendingResumeSeconds {
            // Item chưa sẵn sàng ⇒ đừng ghi đè giây đã lưu bằng 0.
            seconds = pending
        } else if player.currentItem == nil {
            seconds = 0
        } else {
            // Đã hết item (KVO `.paused`, thu nhỏ, vào nền… đến sau `handlePlayedToEnd`) ⇒ giữ giây đã lưu lúc hết
            // tập, không ghi giây ≈ độ dài phim. Phòng thủ thêm khi đầu phát nằm trong giây cuối của item.
            guard !reachedEndOfItem, !isAtEndOfCurrentItem() else { return }
            seconds = currentPlaybackSeconds()
        }

        lastProgressSaveUptime = ProcessInfo.processInfo.systemUptime
        if let last = lastSavedProgress, last.episode == episode.index, last.seconds == seconds { return }
        lastSavedProgress = (episode: episode.index, seconds: seconds)

        let snapshot = ReadingProgressSnapshot(
            bookId: launch.bookId,
            chapterIndex: episode.index,
            paragraphIndex: seconds,
            chapterTitle: episode.title
        )
        Task {
            do {
                try await ReadingProgressStore.shared.checkpoint(snapshot)
            } catch {
                AppLogger.shared.log("❌ [VideoPlayer] Lỗi lưu tiến độ xem (\(reason)): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Vào nền / về trước

    func installLifecycleObservers() {
        guard lifecycleTokens.isEmpty else { return }
        let center = NotificationCenter.default
        let background = center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleDidEnterBackground()
            }
        }
        let foreground = center.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleWillEnterForeground()
            }
        }
        lifecycleTokens = [background, foreground]
    }

    /// Tách `playerLayer.player` khi vào nền mà không có PiP — iOS tự dừng player còn gắn hình ⇒ tách ra để chỉ phát
    /// tiếng. Không tách ở `willResignActive` (giết PiP tự bật). Màn hình đang hiện và đang phát thì PiP sắp tự bật:
    /// chờ một nhịp, PiP không lên thì mới tách và phát tiếp. Nhịp chờ nằm trong background task: lúc đó iOS đã dừng
    /// player (còn gắn hình) nên không còn tiếng giữ app sống — thiếu task thì app có thể bị treo trước khi kịp phát lại.
    private func handleDidEnterBackground() {
        isInBackground = true
        guard launch != nil else { return }
        saveProgress(reason: "vào nền")
        guard embedContent == nil else { return }
        let pip = pictureInPicture
        let expectsAutomaticPiP = isScreenAttached && (pip?.isActiveOrStarting == true || (pip?.isPossible == true && isPlaying))
        guard expectsAutomaticPiP else {
            refreshLayerAttachment()
            return
        }
        let shouldResume = isPlaying
        let backgroundTask = beginAudioFallbackBackgroundTask()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            self?.fallBackToAudioOnlyIfNeeded(resume: shouldResume)
            self?.endAudioFallbackBackgroundTask(backgroundTask)
        }
    }

    /// Mỗi lượt vào nền một task; task cũ (nền → trước → nền trong vòng 1 giây) được kết thúc trước.
    private func beginAudioFallbackBackgroundTask() -> UIBackgroundTaskIdentifier {
        endAudioFallbackBackgroundTask(audioFallbackBackgroundTask)
        let task = UIApplication.shared.beginBackgroundTask(withName: "VideoAudioFallback") { [weak self] in
            // iOS gọi trên main khi hết hạn ⇒ kết thúc task đang giữ (helper kiểm `.invalid`, không kết thúc hai lần).
            let owner = self
            MainActor.assumeIsolated {
                guard let owner else { return }
                owner.endAudioFallbackBackgroundTask(owner.audioFallbackBackgroundTask)
            }
        }
        audioFallbackBackgroundTask = task
        return task
    }

    /// Chỉ kết thúc khi `task` vẫn là task đang giữ: nhịp chờ của lượt vào nền cũ không được kết thúc task của lượt mới.
    private func endAudioFallbackBackgroundTask(_ task: UIBackgroundTaskIdentifier) {
        guard task != .invalid, task == audioFallbackBackgroundTask else { return }
        audioFallbackBackgroundTask = .invalid
        UIApplication.shared.endBackgroundTask(task)
    }

    private func fallBackToAudioOnlyIfNeeded(resume: Bool) {
        guard isInBackground, launch != nil, pictureInPicture?.isActiveOrStarting != true else { return }
        refreshLayerAttachment()
        if resume, player.timeControlStatus == .paused {
            AppLogger.shared.log("🎧 [VideoPlayer] PiP không bật được khi vào nền ⇒ phát tiếp chỉ tiếng")
            player.play()
        }
    }

    private func handleWillEnterForeground() {
        isInBackground = false
        refreshLayerAttachment()
    }

    /// Gắn hình khi: màn hình đang hiện và app ở trước, hoặc PiP đang bật/đang bật dở. Còn lại (đã thu nhỏ, hoặc nền
    /// không PiP) thì tách — player vẫn phát tiếng.
    func refreshLayerAttachment() {
        let pipBusy = pictureInPicture?.isActiveOrStarting ?? false
        let shouldAttach = pipBusy || (isScreenAttached && !isInBackground)
        let isAttached = layerView.playerLayer.player != nil
        guard shouldAttach != isAttached else { return }
        layerView.playerLayer.player = shouldAttach ? player : nil
        refreshBandwidthLimit()
        if launch != nil {
            AppLogger.shared.log(shouldAttach ? "🎬 [VideoPlayer] Gắn lại hình vào player" : "🎧 [VideoPlayer] Tách hình khỏi player ⇒ chỉ phát tiếng")
        }
    }

    /// Đang chỉ phát tiếng (đã tách hình: thu nhỏ / nền không PiP) ⇒ `preferredPeakBitRate = 1` để HLS xuống biến thể
    /// bitrate thấp nhất, đỡ tải hình không ai xem; gắn lại hình ⇒ trần theo mục Chất lượng (`appliedQuality`, `+Quality`)
    /// hoặc `0` (không giới hạn) khi Tự động — chất lượng tự leo lại sau vài đoạn. Chỉ có tác dụng với HLS **nhiều** mức
    /// chất lượng — mp4, playlist một mức hay playlist ghép hình + tiếng (`VideoAudioRenditionComposer`) không giảm được.
    /// Không đổi sang luồng chỉ tiếng: thay item lúc PiP / nền / thu nhỏ làm hỏng các ca đó (xem `+AudioFallback`). Gọi
    /// cả khi item mới vào (item mới mặc định không giới hạn).
    func refreshBandwidthLimit() {
        guard let item = player.currentItem else { return }
        let isHidden = layerView.playerLayer.player == nil
        let cap = isHidden ? nil : appliedQuality
        let peak: Double = isHidden ? 1 : (cap?.peakBitRate ?? 0)
        let resolution = cap.map { $0.width > 0 && $0.height > 0 ? CGSize(width: $0.width, height: $0.height) : .zero } ?? .zero
        guard item.preferredPeakBitRate != peak || item.preferredMaximumResolution != resolution else { return }
        item.preferredPeakBitRate = peak
        item.preferredMaximumResolution = resolution
        let state = isHidden ? "đang ẩn ⇒ chất lượng thấp nhất" : "trần \(cap?.title ?? "không giới hạn")"
        AppLogger.shared.log("🎚️ [VideoPlayer] Giới hạn HLS: \(state)")
    }

    // MARK: - Âm thanh & TTS

    /// TTS đang đọc thì tạm dừng (chỉ gọi hàm, không observe `TTSManager`), chuyển session sang
    /// `.playback` / `.moviePlayback` rồi giữ phiên điều khiển màn khoá. Gọi lại nhiều lần vẫn an toàn.
    /// `claimRemoteControls == false` cho trang nhúng: không điều khiển được media của trang.
    /// Video native đang tắt tiếng mà TTS đang đọc ⇒ không giành gì: TTS đọc tiếp, `AVAudioSession` và màn khoá giữ
    /// nguyên cho TTS. Bật tiếng lại thì `setMuted(false)` gọi lại hàm này để video lấy lại âm thanh.
    func prepareAudioForPlayback(claimRemoteControls: Bool = true) {
        let tts = TTSManager.shared
        if tts.isPlaying {
            guard !isEffectivelyMuted else {
                AppLogger.shared.log("🔇 [VideoPlayer] Video đang tắt tiếng, TTS đang đọc ⇒ không dừng TTS, giữ âm thanh + màn khoá cho TTS")
                return
            }
            AppLogger.shared.log("⏸️ [VideoPlayer] TTS đang đọc ⇒ tạm dừng để phát video")
            tts.pause()
        }

        let session = AVAudioSession.sharedInstance()
        do {
            if session.category != .playback || session.mode != .moviePlayback {
                try session.setCategory(.playback, mode: .moviePlayback)
            }
            try session.setActive(true)
            didActivateAudioSession = true
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không cấu hình được AVAudioSession: \(error.localizedDescription)")
        }

        guard claimRemoteControls else { return }
        // TTS `pause()` ở trên vừa ghi trạng thái của nó ⇒ giành phiên SAU đó để không bị ghi đè.
        VideoNowPlayingCoordinator.shared.claim()
    }

    func deactivateAudioSessionIfIdle() {
        guard didActivateAudioSession else { return }
        didActivateAudioSession = false
        // TTS được bật lại trong lúc xem (widget nổi) thì giữ nguyên session cho nó.
        guard !TTSManager.shared.isPlaying else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            AppLogger.shared.log("❌ [VideoPlayer] Không tắt được AVAudioSession: \(error.localizedDescription)")
        }
    }

    // MARK: - Khoá màn hình

    /// Giữ màn sáng chỉ khi màn trình phát đang hiện và đang phát (native) hoặc đang nhúng trang. Đi qua
    /// `ScreenIdleTimerLock` (dùng chung với màn đọc truyện tranh): video chỉ trả phần của chính nó, không ghi đè giá
    /// trị gốc lẫn nhau. Gọi lặp an toàn.
    func refreshIdleTimer() {
        let owner = ObjectIdentifier(self)
        if launch != nil, isScreenAttached, isPlaying || embedContent != nil {
            ScreenIdleTimerLock.acquire(owner)
        } else {
            ScreenIdleTimerLock.release(owner)
        }
    }
}
