import Foundation

/// Hết tập + chế độ phát playlist của trình phát phim. Hàng đợi do `PlaylistPlaybackCoordinator` giữ; đây là các hàm
/// coordinator gọi vào phiên và các chỗ phiên hỏi coordinator (`isInPlaylistMode`). Nhánh "hết tập" dời khỏi `+Playback`
/// (file đó chạm trần 400 dòng).
extension VideoPlaybackSession {
    /// Đang phát playlist (tập kế / màn khoá theo hàng đợi của coordinator), kể cả lúc chờ phim của mục kế mở.
    var isInPlaylistMode: Bool { PlaylistPlaybackCoordinator.shared.isVideoActive(in: self) }

    /// Có "tiếp theo" cho nút ⏭ của thanh dưới và màn khoá: chế độ playlist ⇒ mục kế của playlist; thường ⇒ tập kế.
    var canPlayNext: Bool {
        isInPlaylistMode ? PlaylistPlaybackCoordinator.shared.videoHasNext : nextEpisode != nil
    }

    /// Item phát hết (`handlePlayedToEnd`): hẹn giờ "Hết tập" (dừng ở cuối) → chế độ playlist (mục kế của playlist, không
    /// sang tập kế, không tự sang phim đề xuất) → tập kế → hết tập cuối thì tự sang phim đề xuất.
    func advanceAfterEpisodeEnded() {
        guard !stopAtEndOfEpisodeForSleepTimer() else { return }
        if PlaylistPlaybackCoordinator.shared.videoEpisodeDidEnd(in: self) { return }
        guard let next = nextEpisode else {
            AppLogger.shared.log("🏁 [VideoPlayer] Đã xem hết tập cuối")
            saveProgress(reason: "hết tập cuối", seconds: 0)
            if let launch {
                VideoAutoNextCoordinator.shared.lastEpisodeDidEnd(launch: launch, isMuted: isMuted, modelContainer: modelContainer)
            }
            return
        }
        AppLogger.shared.log("⏭️ [VideoPlayer] Hết tập \(currentEpisodeIndex) ⇒ sang tập \(next.index)")
        beginEpisodeLoad(next.index, resumeSeconds: 0)
        saveProgress(reason: "sang tập kế", seconds: 0)
    }

    /// Tập của phim đang mở ứng với mục playlist: link tập trước, chỉ số sau; dòng section không tính. `nil` khi phim
    /// không còn tập đó.
    func playlistEpisodeIndex(index: Int, url: String) -> Int? {
        let playable = episodes.filter { !$0.isSection }
        if !url.isEmpty, let match = playable.first(where: { $0.url == url }) { return match.index }
        return playable.first(where: { $0.index == index })?.index
    }

    /// Sang tập `index` của phim đang mở theo playlist — **không** thoát chế độ playlist như `selectEpisode`. `notice` hiện
    /// khi tập mới bắt đầu phát ("Bỏ qua …"). Cùng tập ⇒ đang lỗi thì thử lại, đang dừng thì phát.
    func playPlaylistEpisode(_ index: Int, userInitiated: Bool, notice: String?) {
        guard launch != nil else { return }
        if index == currentEpisodeIndex {
            if case .failed = phase {
                retry()
            } else if !isPlaying {
                play()
            }
            if let notice { showPlaybackNotice(notice) }
            return
        }
        if userInitiated {
            saveProgress(reason: "chọn mục playlist")
            beginUserRequestedPlayback()
        }
        AppLogger.shared.log("⏭️ [VideoPlayer] Playlist: sang tập \(index)")
        beginEpisodeLoad(index, resumeSeconds: 0)
        // `prepareForNewLoad` xoá dòng báo đang hiện ⇒ hiện khi tập mới bắt đầu phát (`showPendingStartNotice`).
        pendingStartNotice = notice
        if !userInitiated { saveProgress(reason: "sang mục playlist", seconds: 0) }
    }

    /// Lỗi của mục đang phát (`fail`, `handleItemFailure`, phim không có tập) ⇒ coordinator bỏ qua sang mục kế (không ở
    /// chế độ playlist thì thôi).
    func notePlaylistFailure(_ message: String) {
        guard let bookId = launch?.bookId else { return }
        PlaylistPlaybackCoordinator.shared.videoSessionItemDidFail(bookId: bookId, message: message)
    }
}
