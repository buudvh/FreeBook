import Foundation

/// Tên hiển thị của phim đang mở — tên phim, tác giả (màn khoá), tên tập, tên nhóm tập: đi `ChineseTextPipeline`, phồn →
/// giản **cả khi tắt dịch**, dịch khi bật (`MediaDisplayNames`, cấu hình phim này ⇒ nguồn ⇒ Tất cả). Tên gốc (`bookTitle`,
/// `Episode.title`) giữ nguyên văn; chỗ vẽ đọc `displayBookTitle`, `Episode.displayTitle` (qua `shownTitle`),
/// `displayNames.author(_:)`. Phim 18+ ở màn khoá vẫn chỉ "Đang phát" (`VideoNowPlayingMetadata`, không đọc tên).
///
/// Tính ngoài main khi nạp mục lục (`start`), khi màn xem nhận mục lục làm mới (`adoptRefreshedEpisodes`) và khi cấu hình
/// dịch / từ điển đổi từ sheet "Dịch phụ đề" / "Từ điển truyện" (`retranslateSubtitles`). Thay `translateSectionTitles` cũ
/// (chỉ dịch tên nhóm tập khi bật dịch, ghi đè `title`).
extension VideoPlaybackSession {
    /// Tên phim để vẽ (thanh trên, chi tiết, hub, màn khoá).
    var displayBookTitle: String { displayNames.title(bookTitle) }

    func refreshDisplayNames() {
        displayNamesTask?.cancel()
        displayNamesTask = nil
        guard let launch else { return }
        let options = ChineseTextPipeline.options(bookId: launch.bookId, packageId: launch.extensionPackageId)
        // Cấu hình như cũ ⇒ gắn ngay tên đã tính cho mục lục vừa thay (khỏi nháy tên gốc), rồi mới tính lại.
        if displayNames.options == options { applyItemNames(displayNames) }
        let empty = MediaDisplayNames(options: options)
        guard !empty.isPassthrough else {
            applyDisplayNames(empty)
            return
        }
        let titles = [bookTitle, launch.bookTitle ?? ""]
        let authors = [resolvedNowPlayingAuthor(), launch.bookAuthor ?? ""]
        let items = episodes.map(\.title)
        let bookId = launch.bookId
        displayNamesTask = Task { [weak self] in
            let names = await Task.detached(priority: .userInitiated) {
                MediaDisplayNames.make(titles: titles, authors: authors, items: items, options: options)
            }.value
            guard let self, !Task.isCancelled, self.launch?.bookId == bookId else { return }
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
        let itemsChanged = applyItemNames(names)
        guard changed || itemsChanged else { return }
        syncMiniPlayerState()
        publishNowPlaying()
    }

    /// Gắn `shownTitle` theo bảng tên (tra theo tên gốc). `true` = có tập đổi tên hiển thị.
    @discardableResult
    private func applyItemNames(_ names: MediaDisplayNames) -> Bool {
        var changed = false
        let updated = episodes.map { episode -> Episode in
            let shown = names.item(episode.title)
            guard shown != episode.shownTitle else { return episode }
            changed = true
            var copy = episode
            copy.shownTitle = shown
            return copy
        }
        if changed { episodes = updated }
        return changed
    }
}
