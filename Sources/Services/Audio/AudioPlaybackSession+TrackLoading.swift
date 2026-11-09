import Foundation

/// Lấy link phát của một bài: `chap` (nguồn đầu tiên có `data`, không có ⇒ URL bài — `SourceRuntime.audioStreamData`) →
/// `track` (`SourceRuntime.audioTrack`: nguồn phát + lời) → `AudioPreparedTrack.playableTrack` (áp `audios[0]`) →
/// `VideoSourceResolver` (`native` phát thẳng, `auto`/`webview` dò link headless; chỉ nhúng được trang ⇒ lỗi).
///
/// - Mỗi lượt nạp gắn `loadGeneration` (`prepareForNewLoad`); lượt cũ về muộn bị bỏ. `CancellationError` không là lỗi.
/// - **Nạp sẵn** bài kế (`autoAdvanceTarget`) khi bài hiện còn ≤ `prefetchLeadSeconds`: chạy đủ `chap` + `track` + dò link
///   bằng resolver riêng, giữ ở `preparedTracks` theo chỉ số bài + lượt mở; sang bài thì dùng ngay nếu chưa quá
///   `AudioPreparedTrack.maxAge`.
extension AudioPlaybackSession {
    // MARK: - Lượt nạp

    /// Nạp bài `index` (chỉ số mục lục). `autoplay`: tự phát khi item sẵn sàng (vẫn tôn trọng cờ nhường TTS / phim).
    func beginTrackLoad(_ index: Int, resumeSeconds: Int, autoplay: Bool) {
        currentTrackIndex = index
        shouldAutoplay = autoplay
        let generation = prepareForNewLoad(resumeSeconds: resumeSeconds)
        phase = .loading
        syncMiniPlayerState()
        publishNowPlayingLoading()
        // Bài cuối (lặp tắt) ⇒ tải sẵn mục gợi ý cho lúc hết album.
        AudioAutoNextCoordinator.shared.trackLoadDidBegin(in: self)
        if prefetchingIndex == index {
            // Lượt nạp sẵn chính bài này chưa xong ⇒ bỏ, nạp thẳng (một nguồn sự thật cho lượt nạp).
            cancelPrefetch()
        }
        if let ready = takePreparedTrack(index) {
            AppLogger.shared.log("🎵 [AudioPlayer] Bài \(index): dùng link đã nạp sẵn")
            apply(prepared: ready, generation: generation)
            return
        }
        loadTask = Task { [weak self] in
            await self?.runTrackLoad(index: index, generation: generation)
        }
    }

    /// Thử lại sau lỗi: chưa có bài ⇒ đọc lại album từ đầu; có ⇒ nạp lại bài đang mở ở giây đang nghe.
    func retry() {
        guard isActive else { return }
        beginUserRequestedPlayback()
        guard let index = currentTrackIndex, track(at: index) != nil else {
            AppLogger.shared.log("🎵 [AudioPlayer] Thử lại: đọc lại album")
            phase = .loading
            beginStart()
            return
        }
        AppLogger.shared.log("🎵 [AudioPlayer] Thử lại bài \(index)")
        beginTrackLoad(index, resumeSeconds: resumePointForReload(), autoplay: true)
    }

    func isCurrentLoad(_ generation: Int) -> Bool {
        generation == loadGeneration && isActive && !Task.isCancelled
    }

    private func runTrackLoad(index: Int, generation: Int) async {
        guard let track = self.track(at: index) else {
            fail(generation: generation, message: PlaybackError.trackNotFound.localizedDescription)
            return
        }
        guard let ext = installedExtension() else {
            AppLogger.shared.log("❌ [AudioPlayer] Tiện ích \(packageId) chưa cài hoặc đã bị gỡ")
            fail(generation: generation, message: missingExtensionMessage())
            return
        }
        let resolver = VideoSourceResolver(extensionPackageId: ext.packageId)
        self.resolver = resolver
        do {
            let prepared = try await prepareTrack(track, ext: ext, resolver: resolver, openGeneration: openGeneration)
            guard isCurrentLoad(generation) else { return }
            self.resolver = nil
            apply(prepared: prepared, generation: generation)
        } catch {
            guard isCurrentLoad(generation), !Self.isCancellation(error) else { return }
            self.resolver = nil
            // `ExtensionManager` / `VideoSourceResolver` đã log ❌ lỗi nguồn; lỗi riêng của trình nghe thì log ở đây.
            if error is PlaybackError {
                AppLogger.shared.log("❌ [AudioPlayer] Bài \(index): \(error.localizedDescription)")
            }
            fail(generation: generation, message: "Không phát được bài này: \(error.localizedDescription)",
                 link: trackErrorLink(for: error, track: track))
        }
    }

    /// `chap` → `track` → dò link. Dùng chung cho lượt nạp và lượt nạp sẵn (resolver riêng mỗi bên).
    func prepareTrack(_ track: Track, ext: Extension, resolver: VideoSourceResolver, openGeneration: Int) async throws -> AudioPreparedTrack {
        let host = ExtensionHostResolver.chapterHost(chapterHost: track.host, bookHost: bookHost, packageId: ext.packageId)
        let data = try await SourceRuntime.shared.audioStreamData(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            url: track.url,
            host: host,
            configJson: ext.configJson
        )
        try Task.checkCancellation()
        let result = try await SourceRuntime.shared.audioTrack(
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            data: data,
            configJson: ext.configJson
        )
        try Task.checkCancellation()
        let playable = AudioPreparedTrack.playableTrack(from: result.track)
        let plan = try await resolver.resolve(playable.track, extensionLocalPath: ext.localPath)
        if case .embed = plan {
            throw PlaybackError.embedOnly
        }
        return AudioPreparedTrack(
            trackIndex: track.index,
            openGeneration: openGeneration,
            plan: plan,
            mimeType: playable.mimeType,
            lyricSources: result.lyrics,
            lyricHeaders: result.track.headers,
            preparedAt: ProcessInfo.processInfo.systemUptime
        )
    }

    /// Link "Mở link lỗi": `fetch` lỗi của lượt chạy script → URL trang bài (ghép host như lúc gọi script).
    func trackErrorLink(for error: Error?, track: Track) -> SourceErrorLink? {
        let host = ExtensionHostResolver.chapterHost(chapterHost: track.host, bookHost: bookHost, packageId: packageId)
        return SourceErrorLink.resolve(from: error, fallback: track.url, host: host)
    }

    /// Lỗi của lượt nạp `generation`: hiện lỗi, gỡ item, trả màn khoá (TTS dựng lại lệnh nếu đang có widget).
    func fail(generation: Int, message: String, link: SourceErrorLink? = nil) {
        guard isCurrentLoad(generation) else { return }
        phase = .failed(message, link: link)
        if player.timeControlStatus != .paused { player.pause() }
        AudioNowPlayingCoordinator.shared.release(handBackToTTS: true)
        syncMiniPlayerState()
        notePlaylistFailure(message)
    }

    // MARK: - Nạp sẵn

    /// Gọi từ tick: bài hiện còn ≤ `prefetchLeadSeconds` ⇒ nạp sẵn bài kế (một lượt một lúc, mỗi bài một lần).
    func prefetchNextIfNeeded() {
        // Hẹn giờ "Hết bài" ⇒ không sang bài kế, khỏi nạp sẵn.
        guard isActive, durationSeconds > 0, durationSeconds - currentSeconds <= Self.prefetchLeadSeconds,
              prefetchingIndex == nil, !sleepTimer.stopsAtEndOfItem,
              let next = autoAdvanceTarget(), next != currentTrackIndex, next != prefetchAttemptedIndex,
              let track = self.track(at: next) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let ready = preparedTracks[next], ready.isUsable(openGeneration: openGeneration, now: now) { return }
        guard let ext = installedExtension() else { return }
        let generation = openGeneration
        let resolver = VideoSourceResolver(extensionPackageId: ext.packageId)
        prefetchResolver = resolver
        prefetchingIndex = next
        prefetchAttemptedIndex = next
        AppLogger.shared.log("🎵 [AudioPlayer] Nạp sẵn link bài kế: \(next)")
        prefetchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let ready = try await self.prepareTrack(track, ext: ext, resolver: resolver, openGeneration: generation)
                guard generation == self.openGeneration, self.prefetchingIndex == next, !Task.isCancelled else { return }
                self.preparedTracks[next] = ready
                AppLogger.shared.log("🎵 [AudioPlayer] Đã nạp sẵn bài \(next)")
            } catch {
                if !AudioPlaybackSession.isCancellation(error) {
                    // Lỗi nguồn đã được log ❌ ở tầng dưới; tới lượt sang bài sẽ nạp lại và báo lỗi nếu còn hỏng.
                    AppLogger.shared.log("⚠️ [AudioPlayer] Nạp sẵn bài \(next) lỗi, sẽ nạp lại khi sang bài: \(error.localizedDescription)")
                }
            }
            if generation == self.openGeneration, self.prefetchingIndex == next {
                self.prefetchingIndex = nil
                self.prefetchResolver = nil
                self.prefetchTask = nil
            }
        }
    }

    func cancelPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchResolver?.cancel()
        prefetchResolver = nil
        prefetchingIndex = nil
    }

    /// Lấy (và bỏ khỏi cache) bản nạp sẵn còn dùng được của bài `index`.
    private func takePreparedTrack(_ index: Int) -> AudioPreparedTrack? {
        guard let ready = preparedTracks.removeValue(forKey: index) else { return nil }
        guard ready.isUsable(openGeneration: openGeneration, now: ProcessInfo.processInfo.systemUptime) else {
            AppLogger.shared.log("🎵 [AudioPlayer] Link nạp sẵn của bài \(index) đã cũ ⇒ nạp lại")
            return nil
        }
        return ready
    }
}
