import Foundation

/// Mọi bài / tập của một album / phim thành mục playlist — lối "Thêm vào playlist" của sheet nhấn giữ trên Kệ.
///
/// Thứ tự: mục lục đã lưu trên máy (`ChapterStore`, theo `bookId`) → không có thì tải mục lục đủ từ tiện ích
/// (`BookDetailLoader.fetchFullTOC`, như trình nghe / màn xem). Dòng `section` bị bỏ; `index` giữ chỉ số thưa của mục lục
/// đủ. **Chỉ đọc** — không ghi mục lục vừa tải xuống máy.
enum PlaylistAlbumItemsLoader {
    static func items(for album: PlaylistAlbumInfo, kind: PlaylistKind) async throws -> [PlaylistItem] {
        let stored = await storedItems(for: album, kind: kind)
        if !stored.isEmpty {
            AppLogger.shared.log("🎶 [Playlist] Lấy \(stored.count) mục từ mục lục trên máy (bookId=\(album.bookId))")
            return stored
        }
        try Task.checkCancellation()

        guard let ext = ExtensionLibraryRepository.snapshot(packageId: album.packageId), !ext.localPath.isEmpty else {
            AppLogger.shared.log("❌ [Playlist] Không có tiện ích chạy được và chưa có mục lục trên máy (tiện ích=\(album.packageId))")
            throw PlaylistError.sourceUnavailable
        }
        let snapshot = ExtensionExecutionSnapshot(
            packageId: ext.packageId,
            name: ext.name,
            localPath: ext.localPath,
            downloadUrl: ext.downloadUrl,
            configJson: ext.configJson
        )
        let context = SourceRuntimeContext(
            bookId: album.bookId.isEmpty ? nil : album.bookId,
            bookUrl: album.detailUrl,
            bookName: album.title.isEmpty ? nil : album.title,
            bookAuthor: album.author.isEmpty ? nil : album.author,
            isInteractive: true
        )
        let result = try await BookDetailLoader.shared.fetchFullTOC(
            snapshot: snapshot,
            url: album.detailUrl,
            host: ExtensionHostResolver.nonEmpty(album.host) ?? ext.sourceUrl,
            context: context
        )
        try Task.checkCancellation()
        let items = result.chapters.enumerated().compactMap { offset, chapter -> PlaylistItem? in
            guard !chapter.isSection else { return nil }
            return PlaylistItemMapper.item(
                kind: kind,
                album: album,
                index: offset,
                chapterUrl: chapter.url,
                title: chapter.name,
                artist: chapter.itemDescription
            )
        }
        guard !items.isEmpty else { throw PlaylistError.emptyAlbum }
        AppLogger.shared.log("🎶 [Playlist] Tải mục lục từ nguồn: \(items.count) mục (tiện ích=\(album.packageId))")
        return items
    }

    /// Mục lục đã lưu (bỏ dòng `section`); đọc lỗi ⇒ log rồi coi như chưa có.
    private static func storedItems(for album: PlaylistAlbumInfo, kind: PlaylistKind) async -> [PlaylistItem] {
        guard !album.bookId.isEmpty else { return [] }
        do {
            let stored = try await ChapterStore.shared.fetchOrderedTOC(bookId: album.bookId)
            return stored.filter { !$0.isSection }.map { chapter in
                PlaylistItemMapper.item(kind: kind, album: album, index: chapter.index, chapterUrl: chapter.url, title: chapter.title)
            }
        } catch {
            AppLogger.shared.log("❌ [Playlist] Lỗi đọc mục lục đã lưu (bookId=\(album.bookId)): \(error.localizedDescription)")
            return []
        }
    }
}
