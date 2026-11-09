import Foundation
import SwiftData

/// Phát playlist **phim** qua `VideoPlaybackSession` / `VideoWatchModel`:
/// - Mục cùng phim đang mở (đã có danh sách tập) ⇒ chuyển tập trong phiên (`playPlaylistEpisode`, không thoát chế độ
///   playlist như `selectEpisode`).
/// - Phim khác ⇒ khuôn `VideoAutoNextCoordinator`: màn xem đang hiện mục của playlist ⇒ đổi tại chỗ (`replace(with:
///   playlistStart:)`), không màn ⇒ `VideoWatchModel` không màn giữ tới khi mở phiên phát (tối đa
///   `videoStartTimeoutNanoseconds`). Model phát luôn dù tắt "Tự phát khi mở phim", đúng tập của mục, từ giây 0, giữ tiếng
///   + hẹn giờ của phim vừa xem. Mỗi lượt có `token`: coordinator đã sang mục khác / thôi playlist ⇒ model cũ không mở phiên.
/// - Hết tập ⇒ mục kế (không lặp, không sang tập kế của phim, không tự sang phim đề xuất). Lỗi (phiên hoặc model) ⇒ "Bỏ qua
///   <tên>: <lý do>" (`playbackNotice` — phim mới hiện khi bắt đầu phát) rồi mục kế; hỏng liên tiếp đủ số mục ⇒ dừng.
extension PlaylistPlaybackCoordinator {
    // MARK: - Trạng thái

    /// Phiên phim đang ở mục của playlist, hoặc đang chờ phim của mục kế mở phiên.
    func isVideoActive(in session: VideoPlaybackSession) -> Bool {
        guard let queue = videoQueue else { return false }
        if queue.pendingToken != nil { return true }
        return !queue.currentBookId.isEmpty && session.launch?.bookId == queue.currentBookId
    }

    var videoHasNext: Bool { videoQueue?.hasNext(wraps: false) ?? false }

    /// Lượt mở `token` còn là lượt coordinator đang chờ (chưa sang mục khác, chưa thôi playlist).
    func acceptsVideoStart(_ token: UUID) -> Bool {
        videoQueue?.pendingToken == token
    }

    // MARK: - Bắt đầu / thoát

    /// Dựng hàng đợi phim từ `itemId` (`nil` = mục đầu). Trả request + lượt mở cho `VideoWatchPresenter` — View trình bày
    /// màn xem; `nil` khi playlist không còn mục nào để phát.
    func startVideo(
        _ playlist: Playlist,
        startingAt itemId: UUID?,
        shuffled: Bool,
        modelContainer: ModelContainer
    ) -> (request: VideoWatchRequest, start: VideoWatchModel.PlaylistStart)? {
        guard var queue = PlaylistPlaybackQueue(playlist: playlist, items: visibleItems(of: playlist), startingAt: itemId, shuffled: shuffled),
              let first = queue.currentItem else {
            AppLogger.shared.log("⚠️ [PlaylistPlayback] Playlist phim «\(playlist.name)» không có mục nào để phát")
            return nil
        }
        releaseVideoHeadless()
        cancelVideoStartTimeout()
        let request = Self.videoRequest(for: first)
        let token = UUID()
        queue.pendingToken = token
        queue.currentBookId = request.resolveBookId(in: modelContainer.mainContext)
        videoContainer = modelContainer
        videoQueue = queue
        armVideoStartTimeout(token)
        AppLogger.shared.log("🎶 [PlaylistPlayback] Phát playlist phim «\(queue.name)» (\(queue.count) tập, xáo: \(shuffled ? "có" : "không"))")
        let start = VideoWatchModel.PlaylistStart(
            token: token,
            episodeUrl: first.chapterUrl,
            muted: nil,
            keepsSleepTimer: false,
            isUserInitiated: true,
            notice: nil
        )
        return (request: request, start: start)
    }

    /// Thôi chế độ playlist (mở phim thường, chọn tập khác, đóng trình phát). Không đụng phiên phát.
    func endVideo(reason: String) {
        guard let queue = videoQueue else { return }
        videoQueue = nil
        releaseVideoHeadless()
        cancelVideoStartTimeout()
        endVideoBackgroundTask()
        AppLogger.shared.log("🎶 [PlaylistPlayback] Thôi phát playlist phim «\(queue.name)» (\(reason))")
    }

    // MARK: - Người dùng / phiên báo

    /// Mục kế (nút của dải playlist, ⏭ của thanh dưới, màn khoá).
    func videoNext(in session: VideoPlaybackSession) {
        refreshVideoQueue()
        guard var queue = videoQueue, let next = queue.moveNext(wraps: false) else { return }
        videoQueue = queue
        playVideoItem(next, in: session, userInitiated: true, notice: nil)
    }

    /// `VideoWatchModel` vừa mở phiên phát (hoặc chuyển tập trong phiên) cho lượt `token`. Model không màn chỉ bị **thả**
    /// (không huỷ): phim đã có mục lục trên máy thì phát trước khi làm mới mục lục xong.
    func videoDidOpen(token: UUID, bookId: String) {
        guard videoQueue?.pendingToken == token else { return }
        videoQueue?.pendingToken = nil
        videoQueue?.currentBookId = bookId
        cancelVideoStartTimeout()
        if videoHeadlessModel?.bookId == bookId { videoHeadlessModel = nil }
    }

    /// Item hết (phiên đã xét hẹn giờ "Hết tập"). `false` ⇒ không ở chế độ playlist (phiên đi đường tập kế / tự sang).
    func videoEpisodeDidEnd(in session: VideoPlaybackSession) -> Bool {
        guard isVideoActive(in: session) else { return false }
        session.saveProgress(reason: "hết mục playlist", seconds: 0)
        // Người dùng vừa bấm mục kế (phim khác đang mở) ⇒ đứng ở cuối chờ phim đó.
        guard videoQueue?.pendingToken == nil else { return true }
        let isAlive = refreshVideoQueue()
        guard var queue = videoQueue else { return true }
        guard isAlive, let next = queue.moveNext(wraps: false) else {
            AppLogger.shared.log("🏁 [PlaylistPlayback] Hết playlist phim «\(queue.name)»\(isAlive ? "" : " (playlist đã bị xoá)") ⇒ dừng ở cuối")
            if !isAlive { endVideo(reason: "playlist đã bị xoá") }
            return true
        }
        videoQueue = queue
        AppLogger.shared.log("⏭️ [PlaylistPlayback] Hết tập ⇒ mục \(queue.displayPosition)/\(queue.count) «\(next.displayTitle(kind: .video))»")
        playVideoItem(next, in: session, userInitiated: false, notice: nil)
        return true
    }

    /// Phiên báo lỗi khi đang ở mục playlist (`fail`, `handleItemFailure`, phim không có tập). Chờ một nhịp, kiểm lại
    /// (vẫn phim đó, vẫn lỗi, người dùng chưa thử lại) rồi bỏ qua.
    func videoSessionItemDidFail(bookId: String, message: String) {
        guard let queue = videoQueue, queue.pendingToken == nil, queue.currentBookId == bookId,
              let item = queue.currentItem else { return }
        beginVideoBackgroundTask()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.skipDelayNanoseconds)
            guard let self else { return }
            let session = VideoPlaybackSession.shared
            guard self.videoQueue?.currentItemId == item.id, self.videoQueue?.pendingToken == nil,
                  session.launch?.bookId == bookId, case .failed = session.phase else { return }
            // Phim đã nhường TTS ⇒ không tự mở mục kế (mở là dừng TTS) — để mục lỗi, người dùng tự chọn tiếp.
            guard !session.autoplayBlockedByTTS else {
                AppLogger.shared.log("⏸️ [PlaylistPlayback] Mục phim lỗi lúc TTS đang đọc ⇒ không tự bỏ qua")
                self.endVideoBackgroundTask()
                return
            }
            self.skipVideo(item, reason: message, in: session)
        }
    }

    /// `VideoWatchModel` của lượt `token` không mở được phiên (tiện ích, mục lục, phim không còn tập của mục).
    func videoStartDidFail(token: UUID, message: String) {
        guard let queue = videoQueue, queue.pendingToken == token, let item = queue.currentItem else { return }
        beginVideoBackgroundTask()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.skipDelayNanoseconds)
            guard let self, self.videoQueue?.pendingToken == token else { return }
            let session = VideoPlaybackSession.shared
            guard !session.autoplayBlockedByTTS else {
                AppLogger.shared.log("⏸️ [PlaylistPlayback] Mục phim không mở được lúc TTS đang đọc ⇒ không tự bỏ qua")
                self.endVideoBackgroundTask()
                return
            }
            self.skipVideo(item, reason: message, in: session)
        }
    }

    /// Mục bắt đầu phát thật ⇒ hết chuỗi lỗi, hết cần giữ app chạy nền.
    func videoItemDidStartPlaying(in session: VideoPlaybackSession) {
        guard let queue = videoQueue, queue.pendingToken == nil, session.launch?.bookId == queue.currentBookId else { return }
        if queue.consecutiveFailures != 0 { videoQueue?.consecutiveFailures = 0 }
        endVideoBackgroundTask()
    }

    // MARK: - Mở mục

    /// Mở `item`: cùng phim đang mở ⇒ chuyển tập trong phiên; khác ⇒ đổi màn xem tại chỗ / model không màn. `notice` hiện
    /// khi mục mới bắt đầu phát.
    func playVideoItem(_ item: PlaylistItem, in session: VideoPlaybackSession, userInitiated: Bool, notice: String?) {
        guard let container = session.modelContainer ?? videoContainer else {
            AppLogger.shared.log("❌ [PlaylistPlayback] Thiếu ModelContainer ⇒ không mở được mục phim")
            endVideo(reason: "thiếu ModelContainer")
            return
        }
        releaseVideoHeadless()
        cancelVideoStartTimeout()
        let request = Self.videoRequest(for: item)
        if let launch = session.launch, !session.episodes.isEmpty,
           isSameFilm(item, request: request, launch: launch, container: container) {
            videoQueue?.pendingToken = nil
            videoQueue?.currentBookId = launch.bookId
            guard let index = session.playlistEpisodeIndex(index: item.index, url: item.chapterUrl) else {
                AppLogger.shared.log("❌ [PlaylistPlayback] Phim không còn tập «\(item.displayTitle(kind: .video))» (chỉ số \(item.index))")
                skipVideo(item, reason: "Phim không còn tập này.", in: session)
                return
            }
            session.playPlaylistEpisode(index, userInitiated: userInitiated, notice: notice)
            return
        }
        let token = UUID()
        let previousBookId = videoQueue?.currentBookId ?? ""
        videoQueue?.pendingToken = token
        videoQueue?.currentBookId = request.resolveBookId(in: container.mainContext)
        let start = VideoWatchModel.PlaylistStart(
            token: token,
            episodeUrl: item.chapterUrl,
            muted: session.isActive ? session.isMuted : nil,
            keepsSleepTimer: true,
            isUserInitiated: userInitiated,
            notice: notice
        )
        if !userInitiated { beginVideoBackgroundTask() }
        armVideoStartTimeout(token)
        if let model = VideoAutoNextCoordinator.shared.visibleScreenModel,
           model.ownsSession || (!previousBookId.isEmpty && model.bookId == previousBookId) {
            AppLogger.shared.log("⏭️ [PlaylistPlayback] Màn xem đổi sang mục phim «\(item.displayTitle(kind: .video))»")
            model.replace(with: request, playlistStart: start)
        } else {
            AppLogger.shared.log("⏭️ [PlaylistPlayback] Không có màn xem ⇒ mở mục phim «\(item.displayTitle(kind: .video))» không màn")
            let model = VideoWatchModel(request: request, modelContainer: container)
            model.playlistStart = start
            videoHeadlessModel = model
            model.start()
        }
    }

    /// Bỏ qua mục lỗi rồi phát mục kế; hỏng liên tiếp đủ số mục ⇒ dừng, thôi chế độ playlist.
    private func skipVideo(_ item: PlaylistItem, reason: String, in session: VideoPlaybackSession) {
        let isAlive = refreshVideoQueue()
        guard var queue = videoQueue else { return }
        queue.consecutiveFailures += 1
        if queue.consecutiveFailures >= max(1, queue.count) {
            AppLogger.shared.log("❌ [PlaylistPlayback] Mọi mục của playlist phim «\(queue.name)» đều lỗi ⇒ dừng")
            if session.isActive { session.showPlaybackNotice(allFailedNotice(queue)) }
            endVideo(reason: "mọi mục đều lỗi")
            return
        }
        let notice = skipNotice(for: item, kind: .video, reason: reason)
        guard isAlive, let next = queue.moveNext(wraps: false) else {
            queue.pendingToken = nil
            videoQueue = queue
            releaseVideoHeadless()
            cancelVideoStartTimeout()
            endVideoBackgroundTask()
            if session.isActive { session.showPlaybackNotice(notice) }
            AppLogger.shared.log("🏁 [PlaylistPlayback] Mục phim cuối lỗi, hết playlist ⇒ dừng")
            return
        }
        videoQueue = queue
        AppLogger.shared.log("⏭️ [PlaylistPlayback] Bỏ qua mục lỗi (\(queue.consecutiveFailures)/\(queue.count)) ⇒ mục \(queue.displayPosition)/\(queue.count)")
        playVideoItem(next, in: session, userInitiated: false, notice: notice)
    }

    // MARK: - Model không màn / hết hạn chờ

    func releaseVideoHeadless() {
        videoHeadlessModel?.cancel()
        videoHeadlessModel = nil
    }

    /// Phim của mục chưa mở phiên sau `videoStartTimeoutNanoseconds`: màn xem đang hiện đúng phim đó (đang tải lâu, tắt
    /// tự phát…) ⇒ chỉ thôi giữ app chạy nền, người dùng vẫn bấm phát được trên màn; còn lại (model không màn, màn đã đóng
    /// giữa chừng) ⇒ bỏ model, thôi chế độ playlist.
    func armVideoStartTimeout(_ token: UUID) {
        videoStartTimeoutTask?.cancel()
        videoStartTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.videoStartTimeoutNanoseconds)
            guard !Task.isCancelled, let self, let queue = self.videoQueue, queue.pendingToken == token else { return }
            self.videoStartTimeoutTask = nil
            self.endVideoBackgroundTask()
            if self.videoHeadlessModel == nil, VideoAutoNextCoordinator.shared.visibleScreenModel?.bookId == queue.currentBookId {
                AppLogger.shared.log("⚠️ [PlaylistPlayback] Mục phim chưa phát sau 90 giây (màn xem đang hiện) ⇒ thôi giữ chạy nền")
                return
            }
            AppLogger.shared.log("❌ [PlaylistPlayback] Mục phim không mở được sau 90 giây ⇒ thôi phát playlist")
            self.endVideo(reason: "hết hạn chờ mục phim")
        }
    }

    func cancelVideoStartTimeout() {
        videoStartTimeoutTask?.cancel()
        videoStartTimeoutTask = nil
    }

    // MARK: - Tiện ích

    @discardableResult
    func refreshVideoQueue() -> Bool {
        guard var queue = videoQueue else { return false }
        let isAlive = queue.refresh(with: playlist(id: queue.playlistId), includeNsfw: includesNsfw)
        if queue != videoQueue { videoQueue = queue }
        return isAlive
    }

    private func isSameFilm(_ item: PlaylistItem, request: VideoWatchRequest, launch: BookContentLaunch, container: ModelContainer) -> Bool {
        if item.packageId == launch.extensionPackageId, item.detailUrl == launch.bookDetailUrl { return true }
        return request.resolveBookId(in: container.mainContext) == launch.bookId
    }

    /// Request mở phim của mục: đúng tập (`episodeIndex`; link tập khớp trước ở `VideoWatchModel.startPlaylistItem`), giây 0.
    static func videoRequest(for item: PlaylistItem) -> VideoWatchRequest {
        VideoWatchRequest(
            packageId: item.packageId,
            detailUrl: item.detailUrl,
            sourceName: item.sourceName ?? "",
            host: item.host,
            title: item.albumTitle.isEmpty ? nil : item.albumTitle,
            coverUrl: item.coverUrl.isEmpty ? nil : item.coverUrl,
            episodeIndex: item.index,
            initialSeconds: 0
        )
    }
}
