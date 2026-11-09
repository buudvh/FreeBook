import Foundation
import SwiftData

/// Phát playlist **nhạc** qua `AudioPlaybackSession`:
/// - Mục cùng album đang mở ⇒ chuyển bài trong phiên (`playPlaylistTrack`, nạp sẵn được — `audioPrefetchTarget`); khác
///   album ⇒ dừng album cũ nhưng **giữ** `AVAudioSession` + màn khoá (`stopSession(keepsPlaybackSession: true)`), giữ hẹn giờ
///   tắt (mốc phút) rồi `open(fromPlaylist: true)` — bài đúng mục (`AudioListenRequest.playlistTrackUrl`), từ giây 0.
/// - Lặp của phiên: `off` ⇒ hết playlist dừng ở cuối; `album` = "Lặp playlist" ⇒ vòng mới (đang xáo thì xáo lại); `one` ⇒
///   phiên tự phát lại bài (không tới đây). Xáo (`isShuffled` của phiên, nhớ toàn app) áp cho thứ tự cả playlist.
/// - Lỗi (`fail` / `failOpen` của phiên) ⇒ chờ `skipDelayNanoseconds`, vẫn lỗi thì "Bỏ qua <tên>: <lý do>"
///   (`AudioPlaybackNotice`) rồi mục kế; hỏng liên tiếp đủ số mục ⇒ dừng.
extension PlaylistPlaybackCoordinator {
    // MARK: - Trạng thái

    /// Trình nghe đang phát playlist (thứ tự / bài sau / lặp / xáo theo hàng đợi).
    func isAudioActive(in session: AudioPlaybackSession) -> Bool {
        audioQueue != nil && session.isActive
    }

    func audioHasNext(in session: AudioPlaybackSession) -> Bool {
        audioQueue?.hasNext(wraps: session.repeatMode == .album) ?? false
    }

    func audioHasPrevious(in session: AudioPlaybackSession) -> Bool {
        audioQueue?.hasPrevious(wraps: session.repeatMode == .album) ?? false
    }

    // MARK: - Bắt đầu / thoát

    /// Phát `playlist` (loại nhạc) từ `itemId` (`nil` = mục đầu của thứ tự phát). `shuffled`: "Phát tất cả" (`false`) /
    /// "Phát ngẫu nhiên" (`true`) đặt lại xáo của trình nghe; chạm một mục (`nil`) giữ xáo đang dùng. `false` khi playlist
    /// không còn mục nào để phát.
    @discardableResult
    func startAudio(_ playlist: Playlist, startingAt itemId: UUID?, shuffled: Bool?, modelContainer: ModelContainer) -> Bool {
        let session = AudioPlaybackSession.shared
        // Chạm đúng mục đang phát của playlist này ⇒ phát tiếp (lỗi thì thử lại), không phát lại từ đầu.
        if let itemId, shuffled == nil, let running = audioQueue, running.playlistId == playlist.id,
           running.currentItemId == itemId, session.isActive, session.bookId == running.currentBookId {
            session.resumeCurrentTrack()
            return true
        }
        let shuffle = shuffled ?? session.isShuffled
        guard let queue = PlaylistPlaybackQueue(playlist: playlist, items: visibleItems(of: playlist), startingAt: itemId, shuffled: shuffle),
              let first = queue.currentItem else {
            AppLogger.shared.log("⚠️ [PlaylistPlayback] Playlist nhạc «\(playlist.name)» không có mục nào để phát")
            return false
        }
        if let shuffled { session.setShuffleForPlaylist(shuffled) }
        audioContainer = modelContainer
        audioQueue = queue
        AppLogger.shared.log("🎶 [PlaylistPlayback] Phát playlist nhạc «\(queue.name)» (\(queue.count) bài, xáo: \(queue.isShuffled ? "có" : "không"))")
        playAudioItem(first, in: session, userInitiated: true, carriesSleepTimer: false)
        return true
    }

    /// Thôi chế độ playlist (mở album thường, chọn bài của album, đóng trình nghe, TTS giành). Không đụng phiên phát.
    func endAudio(reason: String) {
        guard let queue = audioQueue else { return }
        audioQueue = nil
        endAudioBackgroundTask()
        AppLogger.shared.log("🎶 [PlaylistPlayback] Thôi phát playlist nhạc «\(queue.name)» (\(reason))")
    }

    // MARK: - Người dùng chuyển mục

    /// Bài sau (nút, đĩa góc dưới, màn khoá, tai nghe). Hết thứ tự: lặp playlist ⇒ vòng kế; còn lại không làm gì.
    func audioNext(in session: AudioPlaybackSession) {
        refreshAudioQueue()
        let wraps = session.repeatMode == .album
        guard var queue = audioQueue, queue.hasNext(wraps: wraps), let next = queue.moveNext(wraps: wraps) else { return }
        audioQueue = queue
        playAudioItem(next, in: session, userInitiated: true, carriesSleepTimer: true)
    }

    /// Bài trước (phiên đã xét "về đầu bài" khi đang quá 3 giây). `false` ⇒ không có bài trước, phiên tự về đầu bài.
    func audioPrevious(in session: AudioPlaybackSession) -> Bool {
        refreshAudioQueue()
        guard var queue = audioQueue, let previous = queue.movePrevious(wraps: session.repeatMode == .album) else { return false }
        audioQueue = queue
        playAudioItem(previous, in: session, userInitiated: true, carriesSleepTimer: true)
        return true
    }

    /// Chạm một mục ở trang Danh sách của màn nghe. Chính mục đang phát ⇒ lỗi thì thử lại, dừng thì phát.
    func jumpAudio(to itemId: UUID) {
        let session = AudioPlaybackSession.shared
        guard isAudioActive(in: session) else { return }
        refreshAudioQueue()
        guard var queue = audioQueue else { return }
        if queue.currentItemId == itemId, session.bookId == queue.currentBookId {
            session.resumeCurrentTrack()
            return
        }
        guard let item = queue.jump(to: itemId) else { return }
        audioQueue = queue
        playAudioItem(item, in: session, userInitiated: true, carriesSleepTimer: true)
    }

    /// Nút xáo của màn nghe lúc đang phát playlist: dựng lại thứ tự cả playlist, mục đang phát giữ nguyên.
    func audioShuffleDidChange(_ shuffled: Bool) {
        guard var queue = audioQueue else { return }
        queue.setShuffled(shuffled)
        audioQueue = queue
    }

    // MARK: - Phiên báo

    /// Bài kế (chỉ số mục lục) để nạp sẵn: mục kế của vòng hiện tại cùng album đang mở; khác album / hết vòng ⇒ `nil`.
    func audioPrefetchTarget(in session: AudioPlaybackSession) -> Int? {
        guard isAudioActive(in: session), let next = audioQueue?.peekNextItem, isSameAlbumCheap(next, session) else { return nil }
        return session.playlistTrackIndex(index: next.index, url: next.chapterUrl)
    }

    /// Bài phát hết tự nhiên (phiên đã xét hẹn giờ "Hết bài" và lặp một bài). `false` ⇒ không ở chế độ playlist.
    func audioTrackDidEnd(in session: AudioPlaybackSession) -> Bool {
        guard isAudioActive(in: session) else { return false }
        // Phim đang giữ âm thanh ⇒ dừng ở cuối mục, không tự mở mục kế (mở là bắt phim nhường).
        guard !session.autoplayBlockedByOtherMedia else {
            AppLogger.shared.log("⏸️ [PlaylistPlayback] Hết bài lúc phim đang giữ âm thanh ⇒ dừng ở cuối mục")
            session.finishPlaylistAtEnd()
            return true
        }
        let isAlive = refreshAudioQueue()
        guard var queue = audioQueue else { return false }
        guard isAlive, let next = queue.moveNext(wraps: session.repeatMode == .album) else {
            AppLogger.shared.log("🏁 [PlaylistPlayback] Hết playlist nhạc «\(queue.name)»\(isAlive ? "" : " (playlist đã bị xoá)") ⇒ dừng ở cuối")
            session.finishPlaylistAtEnd()
            if !isAlive { endAudio(reason: "playlist đã bị xoá") }
            return true
        }
        audioQueue = queue
        AppLogger.shared.log("⏭️ [PlaylistPlayback] Hết bài ⇒ mục \(queue.displayPosition)/\(queue.count) «\(next.displayTitle(kind: .audio))»")
        session.saveProgress(reason: "hết mục playlist", seconds: 0)
        playAudioItem(next, in: session, userInitiated: false, carriesSleepTimer: true)
        return true
    }

    /// Mục đang mở lỗi (`fail` / `failOpen`). Chờ một nhịp rồi kiểm lại — vẫn đúng album, vẫn lỗi (người dùng chưa thử
    /// lại) — mới bỏ qua.
    func audioItemDidFail(in session: AudioPlaybackSession, message: String) {
        guard isAudioActive(in: session), let item = audioQueue?.currentItem else { return }
        let failedBookId = session.bookId
        beginAudioBackgroundTask()
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.skipDelayNanoseconds)
            guard let self else { return }
            let current = AudioPlaybackSession.shared
            guard self.audioQueue?.currentItemId == item.id, current.isActive, current.bookId == failedBookId,
                  case .failed = current.phase else { return }
            // Phim đang giữ âm thanh ⇒ không tự mở mục kế (mở là bắt phim nhường) — để mục lỗi, người dùng tự chọn tiếp.
            guard !current.autoplayBlockedByOtherMedia else {
                AppLogger.shared.log("⏸️ [PlaylistPlayback] Mục nhạc lỗi lúc phim đang giữ âm thanh ⇒ không tự bỏ qua")
                self.endAudioBackgroundTask()
                return
            }
            self.skipAudio(item, reason: message, in: current)
        }
    }

    /// Bài bắt đầu phát thật ⇒ hết chuỗi lỗi, hết cần giữ app chạy nền.
    func audioItemDidStartPlaying(in session: AudioPlaybackSession) {
        guard isAudioActive(in: session) else { return }
        if audioQueue?.consecutiveFailures != 0 { audioQueue?.consecutiveFailures = 0 }
        endAudioBackgroundTask()
    }

    // MARK: - Mở mục

    /// Mở `item`: cùng album đang mở (mục lục đã có) ⇒ chuyển bài trong phiên; khác ⇒ giữ phiên âm thanh + màn khoá, mở
    /// album của mục. `userInitiated`: người dùng bấm (dừng TTS / phim ngay); tự sang khi hết bài thì giữ cờ nhường phim.
    func playAudioItem(_ item: PlaylistItem, in session: AudioPlaybackSession, userInitiated: Bool, carriesSleepTimer: Bool) {
        guard let container = session.modelContainer ?? audioContainer else {
            AppLogger.shared.log("❌ [PlaylistPlayback] Thiếu ModelContainer ⇒ không mở được mục nhạc")
            endAudio(reason: "thiếu ModelContainer")
            return
        }
        let request = Self.audioRequest(for: item)
        if session.isActive, !session.tracks.isEmpty, isSameAlbum(item, request: request, session: session, container: container) {
            audioQueue?.currentBookId = session.bookId
            guard let index = session.playlistTrackIndex(index: item.index, url: item.chapterUrl) else {
                AppLogger.shared.log("❌ [PlaylistPlayback] Album không còn bài «\(item.displayTitle(kind: .audio))» (chỉ số \(item.index))")
                skipAudio(item, reason: "Album không còn bài này.", in: session)
                return
            }
            session.playPlaylistTrack(index, userInitiated: userInitiated)
            return
        }
        if !userInitiated { beginAudioBackgroundTask() }
        let carriedTimer = carriesSleepTimer ? session.sleepTimer.schedule : nil
        if session.isActive {
            session.stopSession(handingOverToTTS: false, keepsPlaybackSession: true)
        }
        if let carriedTimer { session.sleepTimer.restore(carriedTimer) }
        session.open(request, modelContainer: container, autoplay: true, fromPlaylist: true)
        audioQueue?.currentBookId = session.bookId
    }

    /// Bỏ qua mục lỗi rồi phát mục kế; hỏng liên tiếp đủ số mục ⇒ dừng, thôi chế độ playlist.
    private func skipAudio(_ item: PlaylistItem, reason: String, in session: AudioPlaybackSession) {
        let isAlive = refreshAudioQueue()
        guard var queue = audioQueue else { return }
        queue.consecutiveFailures += 1
        if queue.consecutiveFailures >= max(1, queue.count) {
            AppLogger.shared.log("❌ [PlaylistPlayback] Mọi mục của playlist nhạc «\(queue.name)» đều lỗi ⇒ dừng")
            AudioPlaybackNotice.shared.show(allFailedNotice(queue))
            endAudio(reason: "mọi mục đều lỗi")
            return
        }
        let notice = skipNotice(for: item, kind: .audio, reason: reason)
        AudioPlaybackNotice.shared.show(notice)
        guard isAlive, let next = queue.moveNext(wraps: session.repeatMode == .album) else {
            audioQueue = queue
            endAudioBackgroundTask()
            AppLogger.shared.log("🏁 [PlaylistPlayback] Mục nhạc cuối lỗi, hết playlist ⇒ dừng")
            return
        }
        audioQueue = queue
        AppLogger.shared.log("⏭️ [PlaylistPlayback] Bỏ qua mục lỗi (\(queue.consecutiveFailures)/\(queue.count)) ⇒ mục \(queue.displayPosition)/\(queue.count)")
        playAudioItem(next, in: session, userInitiated: false, carriesSleepTimer: true)
    }

    // MARK: - Tiện ích

    /// Làm mới hàng đợi theo playlist mới nhất. `false` khi playlist đã bị xoá (hàng đợi giữ nguyên).
    @discardableResult
    func refreshAudioQueue() -> Bool {
        guard var queue = audioQueue else { return false }
        let isAlive = queue.refresh(with: playlist(id: queue.playlistId), includeNsfw: includesNsfw)
        if queue != audioQueue { audioQueue = queue }
        return isAlive
    }

    /// So nhanh (không đọc SwiftData): cùng tiện ích + cùng link album với lượt mở hiện tại.
    func isSameAlbumCheap(_ item: PlaylistItem, _ session: AudioPlaybackSession) -> Bool {
        item.packageId == session.packageId && item.detailUrl == session.request?.detailUrl
    }

    private func isSameAlbum(_ item: PlaylistItem, request: AudioListenRequest, session: AudioPlaybackSession, container: ModelContainer) -> Bool {
        if isSameAlbumCheap(item, session) { return true }
        return request.resolveBookId(in: container.mainContext) == session.bookId
    }

    /// Request mở album của mục: đúng bài (link trước, chỉ số sau — `playlistTrackUrl`), từ giây 0.
    static func audioRequest(for item: PlaylistItem) -> AudioListenRequest {
        AudioListenRequest(
            packageId: item.packageId,
            detailUrl: item.detailUrl,
            sourceName: item.sourceName ?? "",
            host: item.host,
            title: item.albumTitle.isEmpty ? nil : item.albumTitle,
            coverUrl: item.coverUrl.isEmpty ? nil : item.coverUrl,
            trackIndex: item.index,
            initialSeconds: 0,
            playlistTrackUrl: item.chapterUrl
        )
    }
}
