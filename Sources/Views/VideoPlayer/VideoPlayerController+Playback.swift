import Foundation
import AVFoundation

/// Dựng `AVPlayerItem` từ `VideoPlaybackPlan`, quan sát trạng thái item / tick 0,5 giây
/// (nút "Bỏ qua", phụ đề, lưu tiến độ định kỳ) và tự sang tập kế khi hết tập.
extension VideoPlayerController {
    // MARK: - Chuẩn bị lượt nạp mới

    /// Huỷ mọi việc của lượt nạp trước, gỡ item cũ, tăng `loadGeneration`. Trả generation mới.
    func prepareForNewLoad(resumeSeconds: Int) -> Int {
        loadTask?.cancel()
        loadTask = nil
        subtitleTask?.cancel()
        subtitleTask = nil
        resolver?.cancel()
        resolver = nil
        detachCurrentItem()
        if embedContent != nil {
            // Trang nhúng không báo pause ⇒ tự trả khoá màn hình khi rời trang.
            setIdleTimerDisabled(false)
            embedContent = nil
        }
        cues = []
        timeSkips = []
        hasSubtitles = false
        if !currentCueText.isEmpty { currentCueText = "" }
        if skipTargetSeconds != nil { skipTargetSeconds = nil }
        pendingResumeSeconds = resumeSeconds > 5 ? resumeSeconds : nil
        loadGeneration += 1
        return loadGeneration
    }

    /// Vị trí cần giữ khi nạp lại cùng tập (đổi server / thử lại).
    func resumePointForReload() -> Int {
        if player.currentItem != nil {
            let seconds = currentPlaybackSeconds()
            if seconds > 5 { return seconds }
        }
        return pendingResumeSeconds ?? 0
    }

    func currentPlaybackSeconds() -> Int {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(seconds)
    }

    // MARK: - Áp kế hoạch phát

    func apply(plan: VideoPlaybackPlan, track: VideoTrack, generation: Int) {
        guard isCurrent(generation) else { return }
        switch plan {
        case .native(let url, let headers):
            AppLogger.shared.log("▶️ [VideoPlayer] Phát native host=\(url.host ?? "?") headers=\(headers.count) server=«\(selectedServerTitle)»")
            // Khoá không công bố chính thức nhưng AVFoundation vẫn đọc (rủi ro đã ghi trong plan, mục 8).
            let options: [String: Any] = headers.isEmpty ? [:] : ["AVURLAssetHTTPHeaderFieldsKey": headers]
            let asset = AVURLAsset(url: url, options: options)
            attach(asset: asset, track: track, generation: generation)
        case .hlsText(let playlist, let baseURL, let headers):
            AppLogger.shared.log("▶️ [VideoPlayer] Phát HLS dạng text (\(playlist.utf8.count) byte) base=\(baseURL?.host ?? "-") server=«\(selectedServerTitle)»")
            let made = HLSPlaylistResourceLoader.makeAsset(playlist: playlist, baseURL: baseURL, headers: headers)
            hlsLoader = made.loader
            attach(asset: made.asset, track: track, generation: generation)
        case .embed(let url, let html, let baseURL):
            // Hợp đồng `VideoPlaybackPlan.embed`: có `url` thì nạp URL, không thì nạp `html` với `baseURL`.
            if let url {
                embedContent = .page(url)
            } else if let html, !html.isEmpty {
                embedContent = .html(html, baseURL: baseURL)
            } else {
                AppLogger.shared.log("❌ [VideoPlayer] Kế hoạch nhúng không có URL lẫn HTML (server «\(selectedServerTitle)»)")
                fail(generation: generation, message: "Không có trang để phát nhúng.")
                return
            }
            AppLogger.shared.log("🌐 [VideoPlayer] Không bắt được link media ⇒ phát nhúng trang (server «\(selectedServerTitle)»)")
            pendingResumeSeconds = nil
            phase = .embed
            prepareAudioForPlayback()
            setIdleTimerDisabled(true)
            // Nhúng thì không biết giây đang xem ⇒ vẫn ghi tập vào Lịch sử với giây = 0.
            saveProgress(reason: "nhúng", seconds: 0)
        }
    }

    private func attach(asset: AVURLAsset, track: VideoTrack, generation: Int) {
        let item = AVPlayerItem(asset: asset)
        observe(item: item)
        timeSkips = track.timeSkips
        player.replaceCurrentItem(with: item)
        phase = .buffering
        loadSubtitles(for: track, generation: generation)
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
        // KVO không chắc giao trên main ⇒ hop qua Task. Chụp `self` (weak) vào hằng trước khi đưa vào
        // closure `@Sendable` của Task — tránh tham chiếu biến `weak var` bắt được.
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
        guard !isTornDown, let item = player.currentItem else { return false }
        return ObjectIdentifier(item) == itemId
    }

    private func handleItemStatusChange(itemId: ObjectIdentifier) {
        guard isCurrentItem(itemId), let item = player.currentItem else { return }
        switch item.status {
        case .readyToPlay:
            guard phase == .buffering else { return }
            if let resume = pendingResumeSeconds {
                pendingResumeSeconds = nil
                player.seek(to: CMTime(seconds: Double(resume), preferredTimescale: 600))
                AppLogger.shared.log("⏩ [VideoPlayer] Tua tới giây đã lưu: \(resume)")
            }
            prepareAudioForPlayback()
            player.play()
            phase = .playing
        case .failed:
            handleItemFailure(itemId: itemId, message: item.error?.localizedDescription ?? "Không rõ lỗi")
        default:
            break
        }
    }

    private func handleItemFailure(itemId: ObjectIdentifier, message: String) {
        guard isCurrentItem(itemId) else { return }
        AppLogger.shared.log("❌ [VideoPlayer] AVPlayerItem lỗi (tập \(currentEpisodeIndex), server «\(selectedServerTitle)»): \(message)")
        phase = .failed("Không phát được video: \(message)")
    }

    private func handleTimeControlChange() {
        guard !isTornDown else { return }
        switch player.timeControlStatus {
        case .playing:
            guard !wasPlaying else { return }
            wasPlaying = true
            // Người dùng có thể bấm play trên điều khiển AVKit sau khi TTS được bật lại ⇒ kiểm tra mỗi lần.
            prepareAudioForPlayback()
            setIdleTimerDisabled(true)
            if phase == .buffering { phase = .playing }
        case .paused:
            guard wasPlaying else { return }
            wasPlaying = false
            setIdleTimerDisabled(false)
            saveProgress(reason: "tạm dừng")
        default:
            break
        }
    }

    private func handlePlayedToEnd(itemId: ObjectIdentifier) {
        guard isCurrentItem(itemId) else { return }
        guard let next = nextEpisode else {
            AppLogger.shared.log("🏁 [VideoPlayer] Đã xem hết tập cuối")
            saveProgress(reason: "hết tập cuối", seconds: 0)
            return
        }
        AppLogger.shared.log("⏭️ [VideoPlayer] Hết tập \(currentEpisodeIndex) ⇒ sang tập \(next.index)")
        beginEpisodeLoad(next.index, resumeSeconds: 0)
        saveProgress(reason: "sang tập kế", seconds: 0)
    }

    // MARK: - Tick 0,5 giây

    private func handleTick(seconds: Double) {
        guard !isTornDown, embedContent == nil, seconds.isFinite else { return }
        updateSkipTarget(at: seconds)
        updateCue(at: seconds)
        if player.timeControlStatus == .playing,
           ProcessInfo.processInfo.systemUptime - lastProgressSaveUptime >= 10 {
            saveProgress(reason: "định kỳ")
        }
    }

    private func updateSkipTarget(at seconds: Double) {
        let milliseconds = seconds * 1000
        let target = timeSkips.first { skip in
            milliseconds >= Double(skip.fromMs) && milliseconds < Double(skip.toMs)
        }.map { Double($0.toMs) / 1000 }
        if target != skipTargetSeconds { skipTargetSeconds = target }
    }

    private func updateCue(at seconds: Double) {
        var text = ""
        if subtitlesEnabled {
            text = cues.first { cue in
                seconds >= Double(cue.start) && seconds < Double(cue.end)
            }?.text ?? ""
        }
        if text != currentCueText { currentCueText = text }
    }

    func skipCurrentSegment() {
        guard let target = skipTargetSeconds else { return }
        skipTargetSeconds = nil
        AppLogger.shared.log("⏭️ [VideoPlayer] Bỏ qua đoạn, tua tới \(Int(target))s")
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600))
    }

    // MARK: - Phụ đề

    func toggleSubtitles() {
        subtitlesEnabled.toggle()
        if !subtitlesEnabled, !currentCueText.isEmpty { currentCueText = "" }
    }

    private func loadSubtitles(for track: VideoTrack, generation: Int) {
        guard let subtitle = track.subtitles.first else { return }
        let headers = track.headers
        subtitleTask = Task { [weak self] in
            do {
                let loaded = try await VideoSubtitleParser.load(subtitle, headers: headers)
                guard let self, self.isCurrent(generation) else { return }
                self.cues = loaded
                self.hasSubtitles = !loaded.isEmpty
                AppLogger.shared.log("💬 [VideoPlayer] Đã nạp phụ đề: \(loaded.count) dòng")
            } catch {
                guard !(error is CancellationError) else { return }
                // Lỗi phụ đề không chặn việc phát.
                AppLogger.shared.log("❌ [VideoPlayer] Không nạp được phụ đề: \(error.localizedDescription)")
            }
        }
    }
}
