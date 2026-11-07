import Foundation

/// Gắn / gỡ **màn hiện hình** của phiên: màn trình phát (`VideoPlayerScreen`, mỗi màn một controller) và cửa sổ nhỏ trong
/// app (`VideoMiniPlayerWindowManager`, 1.3.751). Cả hai đều giữ hình gắn vào player (`refreshLayerAttachment`) và ẩn
/// dòng Video của hub; chỉ màn to mới chặn việc mở lại màn (`requestScreen`).
extension VideoPlaybackSession {
    /// Có màn trình phát (không tính cửa sổ nhỏ) đang gắn.
    var isFullScreenAttached: Bool { !attachedScreens.subtracting(miniPlayerScreens).isEmpty }

    /// `owner` = controller riêng của từng màn (`VideoPlayerController`) hoặc cửa sổ nhỏ (`isMiniPlayer`). Mở lại trình
    /// phát khi màn cũ chưa gỡ xong thì `onAppear` của màn mới có thể tới trước `onDisappear` của màn cũ ⇒ đếm theo từng
    /// màn, không dùng một cờ chung. Màn to gắn vào ⇒ báo cửa sổ nhỏ tự ẩn (`onFullScreenAttached`).
    func attachScreen(_ owner: AnyObject, isMiniPlayer: Bool = false) {
        let id = ObjectIdentifier(owner)
        attachedScreens.insert(id)
        if isMiniPlayer {
            miniPlayerScreens.insert(id)
        } else {
            miniPlayerScreens.remove(id)
        }
        refreshLayerAttachment()
        refreshIdleTimer()
        VideoMiniPlayerState.shared.isActive = false
        if !isMiniPlayer {
            onFullScreenAttached?()
        }
    }

    /// Màn **cuối cùng** biến mất mà session chưa `stop()` ⇒ thu nhỏ vào hub: phim chạy nền, hub hiện mục Video.
    /// Gỡ màn không có trong danh sách (gọi lặp) thì bỏ qua.
    func detachScreen(_ owner: AnyObject) {
        let id = ObjectIdentifier(owner)
        miniPlayerScreens.remove(id)
        guard attachedScreens.remove(id) != nil, attachedScreens.isEmpty else { return }
        refreshLayerAttachment()
        refreshIdleTimer()
        guard launch != nil else {
            VideoMiniPlayerState.shared.reset()
            return
        }
        saveProgress(reason: "thu nhỏ")
        syncMiniPlayerState()
        AppLogger.shared.log("🎬 [VideoPlayer] Thu nhỏ trình phát, phim vẫn chạy nền")
        keepPlayingAfterMinimizeIfNeeded()
    }

    // MARK: - Thu nhỏ không dừng phim (1.3.765)

    /// Màn sắp thu nhỏ (⌄, vuốt xuống, kéo cửa sổ nhỏ vào hub): đang phát thì nhớ để lúc màn cuối rời phiên giữ phát.
    /// Chụp **trước** khi màn đóng — lúc `detachScreen` chạy, player có thể đã bị dừng theo màn. Đang dừng sẵn ⇒ giữ dừng.
    func noteMinimizing() {
        keepPlayingDeadline = isPlaying ? ProcessInfo.processInfo.systemUptime + 3 : 0
    }

    /// Code không tự dừng phim khi thu nhỏ; nếu player vẫn bị dừng (theo màn / lúc tách hình, đổi chất lượng) thì phát
    /// tiếp ngay và kiểm lại sau 1,5 giây. Log để biết nguyên nhân thật trên máy.
    private func keepPlayingAfterMinimizeIfNeeded() {
        guard keepPlayingDeadline > ProcessInfo.processInfo.systemUptime else {
            keepPlayingDeadline = 0
            return
        }
        resumeIfPausedByMinimize(stage: "ngay khi thu nhỏ")
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard let self else { return }
            self.resumeIfPausedByMinimize(stage: "sau 1,5 giây")
            self.keepPlayingDeadline = 0
        }
    }

    private func resumeIfPausedByMinimize(stage: String) {
        guard keepPlayingDeadline > 0, launch != nil, embedContent == nil, player.currentItem != nil,
              !isScreenAttached, !reachedEndOfItem, !autoplayBlockedByTTS,
              isEffectivelyMuted || !TTSManager.shared.isPlaying,
              player.timeControlStatus == .paused else { return }
        AppLogger.shared.log("⏯️ [VideoPlayer] Thu nhỏ: phim bị dừng (\(stage)) ⇒ phát tiếp")
        player.play()
    }

    /// Ghi cầu nối cho hub. Chỉ bật `isActive` khi không màn nào (kể cả cửa sổ nhỏ) đang hiện; closure gán lại mỗi lần vì
    /// `reset()` xoá chúng. Trang nhúng chết cùng màn (WKWebView bị huỷ khi thu nhỏ) ⇒ hub không báo "đang phát" mà mời
    /// chạm để mở lại.
    func syncMiniPlayerState() {
        guard let launch, !isScreenAttached else { return }
        let mini = VideoMiniPlayerState.shared
        let nsfw = RepositoryFilterPolicy.isNsfwBook(bookId: launch.bookId, packageId: launch.extensionPackageId)
        let isEmbed = embedContent != nil
        let subtitle = isEmbed
            ? [currentEpisodeLabel, "Chạm để mở lại"].filter { !$0.isEmpty }.joined(separator: " · ")
            : currentEpisodeLabel
        let playing = isEmbed ? false : isPlaying
        if mini.title != bookTitle { mini.title = bookTitle }
        if mini.subtitle != subtitle { mini.subtitle = subtitle }
        if mini.isPlaying != playing { mini.isPlaying = playing }
        if mini.isNsfw != nsfw { mini.isNsfw = nsfw }
        mini.onTogglePlay = { [weak self] in self?.togglePlayPause() }
        mini.onReopen = { [weak self] in self?.requestScreen() }
        mini.onStop = { [weak self] in self?.stop() }
        if !mini.isActive { mini.isActive = true }
    }

    /// Trình bày lại màn hình gắn với phiên đang chạy (hub, cửa sổ nhỏ, nút phát của mục Video khi đang nhúng). Cửa sổ nhỏ
    /// đang gắn không chặn (chạm vào nó chính là để mở lại màn); `animated == false` khi cửa sổ nhỏ đã tự nở lên.
    func requestScreen(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard launch != nil, !isFullScreenAttached, let handler = presentScreenHandler else {
            completion?()
            return
        }
        handler(animated) {
            completion?()
        }
    }
}
