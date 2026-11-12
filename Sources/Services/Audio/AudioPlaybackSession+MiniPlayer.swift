import Foundation

/// Cầu nối cho đĩa nghe góc dưới (`AudioMiniPlayerState`, 1.3.808 — thay đĩa góc dưới) và lối mở lại màn nghe.
///
/// - Màn nghe gắn / gỡ bằng `attachScreen(_:)` / `detachScreen(_:)` (khoá = đối tượng riêng của từng màn; mở lại màn khi
///   màn cũ chưa gỡ xong thì hai màn cùng gắn trong chốc lát ⇒ đếm theo từng màn). Gỡ màn **không** dừng nhạc.
/// - `requestScreen` gọi `presentScreenHandler` (presenter UI gắn vào) để trình bày lại màn nghe; màn đang hiện thì thôi.
extension AudioPlaybackSession {
    var isScreenAttached: Bool { !attachedScreens.isEmpty }

    func attachScreen(_ owner: AnyObject) {
        attachedScreens.insert(ObjectIdentifier(owner))
        syncMiniPlayerState()
    }

    /// Màn cuối cùng rời ⇒ lưu tiến độ; nhạc vẫn phát (đĩa góc dưới điều khiển).
    func detachScreen(_ owner: AnyObject) {
        guard attachedScreens.remove(ObjectIdentifier(owner)) != nil, attachedScreens.isEmpty else { return }
        saveProgress(reason: "đóng màn nghe")
        syncMiniPlayerState()
    }

    /// Trình bày lại màn nghe gắn với phiên đang chạy (sheet điều khiển nhanh của đĩa góc dưới, màn khoá). Không có presenter / màn đang hiện ⇒ chỉ
    /// gọi `completion`.
    func requestScreen(animated: Bool = true, completion: (() -> Void)? = nil) {
        guard isActive, !isScreenAttached, let handler = presentScreenHandler else {
            completion?()
            return
        }
        handler(animated) {
            completion?()
        }
    }

    /// Ghi cầu nối (chỉ giá trị đổi); closure gán lại mỗi lần vì `reset()` xoá chúng.
    func syncMiniPlayerState() {
        let mini = AudioMiniPlayerState.shared
        guard isActive else {
            if mini.isActive { mini.reset() }
            return
        }
        let nsfw = RepositoryFilterPolicy.isNsfwBook(bookId: bookId, packageId: packageId)
        if isNsfw != nsfw { isNsfw = nsfw }
        let isLoading = phase == .loading || phase == .buffering
        let isFailed: Bool
        if case .failed = phase { isFailed = true } else { isFailed = false }
        let trackTitle = currentTrack?.displayTitle ?? ""
        let hasNext = hasNextTrack
        if mini.bookId != bookId { mini.bookId = bookId }
        if mini.trackTitle != trackTitle { mini.trackTitle = trackTitle }
        if mini.artist != currentArtist { mini.artist = currentArtist }
        let shownAlbumTitle = displayAlbumTitle
        if mini.albumTitle != shownAlbumTitle { mini.albumTitle = shownAlbumTitle }
        if mini.coverUrl != coverUrl { mini.coverUrl = coverUrl }
        if mini.isPlaying != isPlaying { mini.isPlaying = isPlaying }
        if mini.isLoading != isLoading { mini.isLoading = isLoading }
        if mini.isFailed != isFailed { mini.isFailed = isFailed }
        if mini.isNsfw != isNsfw { mini.isNsfw = isNsfw }
        if mini.hasNextTrack != hasNext { mini.hasNextTrack = hasNext }
        if mini.isScreenPresented != isScreenAttached { mini.isScreenPresented = isScreenAttached }
        syncMiniProgress()
        mini.onTogglePlay = { [weak self] in self?.togglePlayPause() }
        mini.onNext = { [weak self] in self?.next() }
        mini.onPrevious = { [weak self] in self?.previous() }
        mini.onReopen = { [weak self] in self?.requestScreen() }
        mini.onStop = { [weak self] in self?.stop() }
        if !mini.isActive { mini.isActive = true }
    }

    /// Tiến độ `0…1` của bài đang phát — chỉ ghi khi lệch ≥ 0,5% (tránh vẽ lại đĩa góc dưới mỗi tick).
    func syncMiniProgress() {
        guard isActive else { return }
        let progress = durationSeconds > 0 ? min(1, max(0, currentSeconds / durationSeconds)) : 0
        guard abs(progress - lastMiniProgress) >= 0.005 || (progress == 0 && lastMiniProgress != 0) else { return }
        lastMiniProgress = progress
        AudioMiniPlayerState.shared.progress = progress
    }
}
