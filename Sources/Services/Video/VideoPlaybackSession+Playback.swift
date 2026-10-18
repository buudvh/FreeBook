import Foundation
import AVFoundation

/// Dựng `AVPlayerItem` từ `VideoPlaybackPlan`, quan sát trạng thái item / tick 0,5 giây (thời gian, phần đã đệm,
/// nút "Bỏ qua", phụ đề, lưu tiến độ định kỳ) và tự sang tập kế khi hết tập (bỏ qua dòng section).
extension VideoPlaybackSession {
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
            embedContent = nil
            // Trang nhúng không báo pause ⇒ tự trả khoá màn hình khi rời trang.
            refreshIdleTimer()
        }
        resetPlaybackSource()
        cues = []
        timeSkips = []
        hasSubtitles = false
        if !currentCueText.isEmpty { currentCueText = "" }
        if skipTargetSeconds != nil { skipTargetSeconds = nil }
        currentSeconds = 0
        durationSeconds = 0
        bufferedSeconds = 0
        reachedEndOfItem = false
        pendingResumeSeconds = resumeSeconds > 5 ? resumeSeconds : nil
        // Màn khoá không chạy tiếp đồng hồ của item cũ trong lúc nạp item mới.
        VideoNowPlayingCoordinator.shared.publishLoading(title: currentEpisodeLabel, album: bookTitle)
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
        Int(currentPlaybackTime)
    }

    /// Đầu phát nằm trong giây cuối của item (độ dài hữu hạn) — lưu lúc này sẽ ghi giây ≈ độ dài phim.
    func isAtEndOfCurrentItem() -> Bool {
        guard let item = player.currentItem else { return false }
        let duration = item.duration.seconds
        let current = item.currentTime().seconds
        guard duration.isFinite, duration > 0, current.isFinite else { return false }
        return current >= duration - 1
    }

    // MARK: - Áp kế hoạch phát

    func apply(plan: VideoPlaybackPlan, track: VideoTrack, generation: Int) {
        guard isCurrent(generation) else { return }
        switch plan {
        case .native(let url, let headers):
            AppLogger.shared.log("▶️ [VideoPlayer] Phát native host=\(url.host ?? "?") headers=\(headers.count) mime=\(track.mimeType ?? "-") server=«\(selectedServerTitle)»")
            let options = Self.assetOptions(headers: headers, mimeType: track.mimeType)
            let asset = AVURLAsset(url: url, options: options)
            attach(asset: asset, track: track, generation: generation)
        case .hlsText(let playlist, let baseURL, let headers, let subPlaylists):
            let extra = subPlaylists.isEmpty ? "" : " + \(subPlaylists.count) playlist con kèm"
            AppLogger.shared.log("▶️ [VideoPlayer] Phát HLS dạng text (\(playlist.utf8.count) byte\(extra)) base=\(baseURL?.host ?? "-") server=«\(selectedServerTitle)»")
            let made = HLSPlaylistResourceLoader.makeAsset(playlist: playlist, baseURL: baseURL, headers: headers, subPlaylists: subPlaylists)
            hlsLoader = made.loader
            attach(asset: made.asset, track: track, generation: generation)
        case .embed(let url, let html, let baseURL):
            // Hợp đồng `VideoPlaybackPlan.embed`: có `url` thì nạp URL, không thì nạp `html` với `baseURL`.
            // Chỉ `User-Agent` và `Referer` (của `track.headers`) tới được trang; thiếu thì UA iPhone Safari
            // dùng chung và Referer = trang/host chứa khung nhúng.
            let userAgent = Self.headerValue("User-Agent", in: track.headers) ?? VideoMediaSniffer.userAgent
            if let url {
                let referer = Self.headerValue("Referer", in: track.headers) ?? baseURL?.absoluteString
                embedContent = .page(url, referer: referer, userAgent: userAgent)
            } else if let html, !html.isEmpty {
                embedContent = .html(html, baseURL: baseURL, userAgent: userAgent)
            } else {
                AppLogger.shared.log("❌ [VideoPlayer] Kế hoạch nhúng không có URL lẫn HTML (server «\(selectedServerTitle)»)")
                fail(generation: generation, message: "Không có trang để phát nhúng.")
                return
            }
            AppLogger.shared.log("🌐 [VideoPlayer] Không bắt được link media ⇒ phát nhúng trang (server «\(selectedServerTitle)»)")
            pendingResumeSeconds = nil
            phase = .embed
            prepareAudioForPlayback(claimRemoteControls: false)
            // Không điều khiển được media của trang ⇒ không giữ phiên màn khoá (gọi SAU khi đã tạm dừng TTS).
            VideoNowPlayingCoordinator.shared.release(handBackToTTS: true)
            refreshIdleTimer()
            syncMiniPlayerState()
            // Nhúng thì không biết giây đang xem ⇒ vẫn ghi tập vào Lịch sử với giây = 0 (tự chuyển sang nhúng vì mất
            // tiếng thì giữ giây đang xem — `embedProgressSeconds`).
            saveProgress(reason: "nhúng", seconds: embedProgressSeconds)
        }
    }

    /// UA đi qua `AVURLAssetHTTPUserAgentKey` (iOS 16+) — UA nằm trong header fields có thể bị AVFoundation bỏ qua;
    /// header còn lại qua `"AVURLAssetHTTPHeaderFieldsKey"` (khoá không công bố nhưng AVFoundation vẫn đọc).
    /// `mimeType` của track ⇒ `AVURLAssetOverrideMIMETypeKey` (iOS 17+, khớp deployment target).
    static func assetOptions(headers: [String: String], mimeType: String?) -> [String: Any] {
        var options: [String: Any] = [:]
        var fields: [String: String] = [:]
        for (key, value) in headers where !isHeader(key, named: "User-Agent") {
            fields[key] = value
        }
        if let userAgent = headerValue("User-Agent", in: headers) {
            options[AVURLAssetHTTPUserAgentKey] = userAgent
        }
        if !fields.isEmpty {
            options["AVURLAssetHTTPHeaderFieldsKey"] = fields
        }
        if let mime = mimeType?.trimmingCharacters(in: .whitespacesAndNewlines), !mime.isEmpty {
            options[AVURLAssetOverrideMIMETypeKey] = mime
        }
        return options
    }

    /// Giá trị header (so tên không phân biệt hoa thường), bỏ giá trị rỗng/khoảng trắng.
    static func headerValue(_ name: String, in headers: [String: String]) -> String? {
        headers.first { isHeader($0.key, named: name) && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty }?.value
    }

    private static func isHeader(_ key: String, named name: String) -> Bool {
        key.caseInsensitiveCompare(name) == .orderedSame
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
        guard launch != nil, let item = player.currentItem else { return false }
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
                currentSeconds = Double(resume)
                AppLogger.shared.log("⏩ [VideoPlayer] Tua tới giây đã lưu: \(resume)")
            }
            refreshTimeline()
            guard !autoplayBlockedByTTS, !TTSManager.shared.isPlaying else {
                // Video đã nhường TTS / TTS đang đọc ⇒ chỉ chuẩn bị item, chờ người dùng bấm phát. `rate` còn khác 0
                // (thay item khi đang phát) thì AVPlayer sẽ tự phát ⇒ dừng hẳn.
                autoplayBlockedByTTS = true
                if player.timeControlStatus != .paused { player.pause() }
                phase = .playing
                AppLogger.shared.log("⏸️ [VideoPlayer] Item sẵn sàng nhưng TTS đang đọc / video đã nhường TTS ⇒ không tự phát")
                return
            }
            prepareAudioForPlayback()
            // `play()` dùng `defaultRate` ⇒ giữ tốc độ người dùng chọn qua các tập.
            player.play()
            phase = .playing
            publishNowPlaying()
        case .failed:
            handleItemFailure(itemId: itemId, message: item.error?.localizedDescription ?? "Không rõ lỗi")
        default:
            break
        }
    }

    private func handleItemFailure(itemId: ObjectIdentifier, message: String) {
        guard isCurrentItem(itemId) else { return }
        // Log ❌ kèm nguồn + URL đã che; phương án dự phòng (mất tiếng) lỗi thì sang phương án kế thay vì báo lỗi.
        guard !logItemFailureAndTryFallback(message: message) else { return }
        phase = .failed("Không phát được video: \(message)")
        // Không còn item phát ⇒ không giữ phiên màn khoá (TTS dựng lại lệnh của nó nếu đang có widget).
        VideoNowPlayingCoordinator.shared.release(handBackToTTS: true)
    }

    func handleTimeControlChange() {
        let status = player.timeControlStatus
        let playing = status != .paused
        if isPlaying != playing { isPlaying = playing }
        let buffering = status == .waitingToPlayAtSpecifiedRate
        if isBuffering != buffering { isBuffering = buffering }
        refreshIdleTimer()
        guard launch != nil else { return }
        switch status {
        case .playing:
            if !wasPlaying {
                wasPlaying = true
                // Xem lại sau khi hết tập cuối ⇒ lượt tạm dừng sau đó lại được lưu.
                reachedEndOfItem = false
                // Phát thật (kể cả nút phát của PiP, đi thẳng vào `AVPlayer`) ⇒ không còn nhường TTS.
                autoplayBlockedByTTS = false
                // Phát lại từ màn khoá / hub sau khi TTS được bật lại ⇒ kiểm tra mỗi lần.
                prepareAudioForPlayback()
                if phase == .buffering { phase = .playing }
            }
            scheduleAudioCheckIfNeeded()
        case .paused:
            if wasPlaying {
                wasPlaying = false
                // KVO `.paused` đến SAU `handlePlayedToEnd` ⇒ đừng ghi đè giây 0 bằng giây ≈ độ dài phim.
                if !reachedEndOfItem { saveProgress(reason: "tạm dừng") }
            }
        default:
            break
        }
        syncMiniPlayerState()
        publishNowPlaying()
    }

    private func handlePlayedToEnd(itemId: ObjectIdentifier) {
        guard isCurrentItem(itemId) else { return }
        reachedEndOfItem = true
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
        guard launch != nil, embedContent == nil, seconds.isFinite else { return }
        if abs(currentSeconds - seconds) >= 0.2 { currentSeconds = max(0, seconds) }
        refreshTimeline()
        updateSkipTarget(at: seconds)
        updateCue(at: seconds)
        if player.timeControlStatus == .playing,
           ProcessInfo.processInfo.systemUptime - lastProgressSaveUptime >= 10 {
            saveProgress(reason: "định kỳ")
        }
        if VideoNowPlayingCoordinator.shared.needsRepublish() {
            publishNowPlaying()
        }
    }

    /// Độ dài và phần đã đệm (khoảng `loadedTimeRanges` chứa đầu phát).
    func refreshTimeline() {
        guard let item = player.currentItem else { return }
        let duration = item.duration.seconds
        let newDuration = duration.isFinite && duration > 0 ? duration : 0
        if newDuration != durationSeconds { durationSeconds = newDuration }
        let current = item.currentTime().seconds
        guard current.isFinite else { return }
        var buffered = 0.0
        for value in item.loadedTimeRanges {
            let range = value.timeRangeValue
            let start = range.start.seconds
            let end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, current >= start - 1, current <= end + 1 else { continue }
            buffered = max(buffered, end)
        }
        if abs(buffered - bufferedSeconds) >= 0.5 { bufferedSeconds = buffered }
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
        seek(to: target)
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
