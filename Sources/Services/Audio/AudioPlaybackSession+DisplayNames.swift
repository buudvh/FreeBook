import Foundation

/// Tên hiển thị của album đang mở — tên album, tác giả / nghệ sĩ, tên bài: đi `ChineseTextPipeline`, phồn → giản **cả khi
/// tắt dịch**, dịch khi bật (`MediaDisplayNames`, cấu hình album này ⇒ nguồn ⇒ Tất cả). Tên gốc (`albumTitle`,
/// `albumAuthor`, `Track.title`, `Track.artist`) giữ nguyên văn — còn ghi `Book`, mục lục, playlist; chỗ vẽ đọc
/// `displayAlbumTitle`, `displayAlbumAuthor`, `currentArtist`, `Track.displayTitle` (qua `shownTitle`). Nguồn 18+ ở màn
/// khoá vẫn chỉ "Đang phát" (`AudioNowPlayingMetadata`, không đọc tên).
///
/// Tính ngoài main khi bắt đầu phát (`beginPlayback`), khi chi tiết về (đổi tên album / tác giả), khi làm mới mục lục ở nền
/// và khi cấu hình dịch đổi từ sheet "Dịch lời" (`retranslateLyrics`).
extension AudioPlaybackSession {
    /// Tên album để vẽ (đầu màn nghe, ngăn kéo, đĩa góc dưới, màn khoá).
    var displayAlbumTitle: String { displayNames.title(albumTitle) }
    /// Tác giả album để vẽ (ngăn kéo `…`, dòng nghệ sĩ khi bài không có nghệ sĩ riêng).
    var displayAlbumAuthor: String { displayNames.author(albumAuthor) }

    func refreshDisplayNames() {
        displayNamesTask?.cancel()
        displayNamesTask = nil
        guard isActive else { return }
        let options = ChineseTextPipeline.options(bookId: bookId, packageId: packageId)
        // Cấu hình như cũ ⇒ gắn ngay tên đã tính cho danh sách bài vừa thay (khỏi nháy tên gốc), rồi mới tính lại.
        if displayNames.options == options { applyTrackNames(displayNames) }
        let empty = MediaDisplayNames(options: options)
        guard !empty.isPassthrough else {
            applyDisplayNames(empty)
            return
        }
        let titles = [albumTitle]
        let authors = [albumAuthor] + tracks.map(\.artist)
        let items = tracks.map(\.title)
        let targetBookId = bookId
        displayNamesTask = Task { [weak self] in
            let names = await Task.detached(priority: .userInitiated) {
                MediaDisplayNames.make(titles: titles, authors: authors, items: items, options: options)
            }.value
            guard let self, !Task.isCancelled, self.bookId == targetBookId else { return }
            self.displayNamesTask = nil
            self.applyDisplayNames(names)
        }
    }

    func resetDisplayNames() {
        displayNamesTask?.cancel()
        displayNamesTask = nil
        if displayNames != .passthrough { displayNames = .passthrough }
    }

    // MARK: - Nội bộ

    private func applyDisplayNames(_ names: MediaDisplayNames) {
        let changed = names != displayNames
        if changed { displayNames = names }
        let tracksChanged = applyTrackNames(names)
        guard changed || tracksChanged else { return }
        syncMiniPlayerState()
        // Chưa có item ⇒ lượt ghi màn khoá kế tiếp (bài sẵn sàng) tự lấy tên mới.
        publishNowPlaying()
    }

    /// Gắn `shownTitle` theo bảng tên (tra theo tên gốc). `true` = có bài đổi tên hiển thị.
    @discardableResult
    private func applyTrackNames(_ names: MediaDisplayNames) -> Bool {
        var changed = false
        let updated = tracks.map { track -> Track in
            let shown = names.item(track.title)
            guard shown != track.shownTitle else { return track }
            changed = true
            var copy = track
            copy.shownTitle = shown
            return copy
        }
        if changed { tracks = updated }
        return changed
    }
}
