import Foundation

/// Chế độ phát playlist của trình nghe — hàng đợi do `PlaylistPlaybackCoordinator` giữ; đây là các hàm coordinator gọi vào
/// phiên và các chỗ phiên hỏi coordinator (`isInPlaylistMode`). Đang ở chế độ playlist thì bài sau / bài trước / có bài
/// sau / hết bài / xáo đi theo hàng đợi (`+Queue`), không theo thứ tự album; `AudioAutoNextCoordinator` đứng ngoài.
extension AudioPlaybackSession {
    /// Đang phát playlist.
    var isInPlaylistMode: Bool { PlaylistPlaybackCoordinator.shared.isAudioActive(in: self) }

    /// Tên chế độ lặp trên nút: ở chế độ playlist, `album` = "Lặp playlist".
    var repeatModeTitle: String { repeatMode.title(inPlaylist: isInPlaylistMode) }

    /// Bài của album đang mở ứng với mục playlist: link bài trước (mục lục nguồn có thể chèn bài ở đầu), chỉ số sau.
    /// `nil` khi album không còn bài đó.
    func playlistTrackIndex(index: Int, url: String) -> Int? {
        if !url.isEmpty, let match = tracks.first(where: { $0.url == url }) { return match.index }
        return track(at: index)?.index
    }

    /// Sang bài `index` của album đang mở theo playlist. `userInitiated`: người dùng bấm — lưu tiến độ bài cũ, dừng TTS /
    /// cho phim nhường ngay như chọn bài; tự sang khi hết bài thì như `advanceAfterTrackEnded` (giữ cờ nhường phim). Cùng bài
    /// đang mở (playlist một mục, lặp playlist) ⇒ phát lại từ đầu; đang lỗi thì thử lại.
    func playPlaylistTrack(_ index: Int, userInitiated: Bool) {
        guard isActive, track(at: index) != nil else { return }
        if index == currentTrackIndex {
            if case .failed = phase {
                retry()
            } else {
                seek(to: 0)
                play()
            }
            return
        }
        if userInitiated {
            saveProgress(reason: "chọn mục playlist")
            beginUserRequestedPlayback()
        }
        AppLogger.shared.log("⏭️ [AudioPlayer] Playlist: sang bài \(index)")
        beginTrackLoad(index, resumeSeconds: 0, autoplay: true)
        if !userInitiated { saveProgress(reason: "sang mục playlist", seconds: 0) }
    }

    /// Chọn lại mục đang phát (trang Danh sách): đang lỗi ⇒ thử lại, đang dừng ⇒ phát.
    func resumeCurrentTrack() {
        guard isActive else { return }
        if case .failed = phase {
            retry()
        } else if !isPlaying {
            play()
        }
    }

    /// "Phát tất cả" (tắt) / "Phát ngẫu nhiên" (bật) của trang playlist — nhớ toàn app như nút xáo. Album đang mở dựng lại
    /// thứ tự cho lúc thôi chế độ playlist.
    func setShuffleForPlaylist(_ shuffled: Bool) {
        guard isShuffled != shuffled else { return }
        isShuffled = shuffled
        AudioPlaybackPreferences.isShuffled = shuffled
        if isActive { resetPlayOrder(startingWith: currentTrackIndex ?? tracks.first?.index ?? 0) }
        AppLogger.shared.log("🔀 [AudioPlayer] Xáo trộn (phát playlist): \(shuffled ? "bật" : "tắt")")
    }

    /// Hết playlist (không lặp): như nhánh "hết album" của `advanceAfterTrackEnded` — dừng ở cuối, **không** tự phát gợi ý.
    func finishPlaylistAtEnd() {
        saveProgress(reason: "hết playlist", seconds: 0)
        phase = .paused
        syncMiniPlayerState()
        publishNowPlaying()
    }

    /// Lỗi của lượt mở / lượt nạp bài (`fail`, `failOpen`) ⇒ coordinator bỏ qua mục playlist đang mở (không ở chế độ
    /// playlist thì thôi).
    func notePlaylistFailure(_ message: String) {
        PlaylistPlaybackCoordinator.shared.audioItemDidFail(in: self, message: message)
    }
}
