import Foundation

/// Lượt mở một mục của playlist phim (`playlistStart`, do `PlaylistPlaybackCoordinator` đặt): khi mục lục sẵn sàng
/// (`considerAutoplay`) chọn **đúng tập** của mục — link tập trước, `request.episodeIndex` sau — rồi phát luôn (dù tắt "Tự
/// phát khi mở phim"), từ giây 0. Không còn tập đó / model không tải được phim (`+Loading`) ⇒ báo coordinator để bỏ qua mục.
extension VideoWatchModel {
    func startPlaylistItem() {
        guard let start = playlistStart else { return }
        let coordinator = PlaylistPlaybackCoordinator.shared
        guard coordinator.acceptsVideoStart(start.token) else {
            playlistStart = nil
            AppLogger.shared.log("⏭️ [VideoWatch] Lượt mở mục playlist đã cũ ⇒ bỏ (bookId=\(bookId))")
            return
        }
        let playable = episodes.filter { !$0.isSection }
        let byUrl = start.episodeUrl.isEmpty ? nil : playable.first(where: { $0.url == start.episodeUrl })
        guard let target = byUrl ?? playable.first(where: { $0.index == request.episodeIndex }) else {
            AppLogger.shared.log("❌ [VideoWatch] Phim không còn tập của mục playlist (chỉ số \(request.episodeIndex ?? -1), bookId=\(bookId))")
            notePlaylistFailure("Phim không còn tập này.")
            return
        }
        if ownsSession {
            // Phiên đang chạy đúng phim này (mở lại màn / mục đầu trùng phim đang phát) ⇒ chỉ chuyển tập trong phiên.
            playlistStart = nil
            coordinator.videoDidOpen(token: start.token, bookId: bookId)
            session.playPlaylistEpisode(target.index, userInitiated: start.isUserInitiated, notice: start.notice)
            return
        }
        play(episodeIndex: target.index, isUserInitiated: start.isUserInitiated)
    }

    /// Model của lượt mở mục playlist không mở được phiên (tiện ích, mục lục, không còn tập) ⇒ coordinator bỏ qua mục.
    /// Lượt mở thường (`playlistStart == nil`) thì thôi.
    func notePlaylistFailure(_ message: String) {
        guard let start = playlistStart else { return }
        playlistStart = nil
        PlaylistPlaybackCoordinator.shared.videoStartDidFail(token: start.token, message: message)
    }
}
