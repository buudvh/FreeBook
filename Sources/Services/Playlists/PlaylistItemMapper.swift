import Foundation
import SwiftData

/// Converter thuần: dựng `PlaylistAlbumInfo` / `PlaylistItem` / `PlaylistAddRequest` từ chỗ đang mở — phiên nghe
/// (`AudioPlaybackSession`), phiên phát phim (`VideoPlaybackSession`), màn xem (`VideoWatchModel`), `Book` trên Kệ hoặc
/// một item danh sách chưa mở (Khám phá, Tìm, Thể loại, gợi ý nhạc, đề xuất phim).
///
/// Quy ước mục:
/// - Nhạc: dòng phụ = nghệ sĩ của bài (`Track.artist`), không có thì tác giả album; `albumTitle` = tên album.
/// - Video: dòng phụ = tên phim; `albumTitle` = tên phim.
/// - `index` = chỉ số thưa của mục lục đủ (`Track.index` / `Episode.index`); bìa = bìa album / phim.
@MainActor
enum PlaylistItemMapper {
    // MARK: - Album

    static func album(of session: AudioPlaybackSession) -> PlaylistAlbumInfo? {
        guard let request = session.request, !session.packageId.isEmpty else { return nil }
        return PlaylistAlbumInfo(
            bookId: session.bookId,
            packageId: session.packageId,
            detailUrl: request.detailUrl,
            title: session.albumTitle,
            author: session.albumAuthor,
            coverUrl: session.coverUrl,
            host: ExtensionHostResolver.nonEmpty(request.host) ?? ExtensionHostResolver.nonEmpty(session.bookHost),
            sourceName: nonEmpty(request.sourceName)
        )
    }

    static func album(of session: VideoPlaybackSession) -> PlaylistAlbumInfo? {
        guard let launch = session.launch, !launch.extensionPackageId.isEmpty else { return nil }
        let book = session.fetchBook()
        let cover = nonEmpty(launch.bookCoverUrl) ?? book?.coverUrl ?? ""
        return PlaylistAlbumInfo(
            bookId: launch.bookId,
            packageId: launch.extensionPackageId,
            detailUrl: nonEmpty(launch.bookDetailUrl) ?? book?.detailUrl ?? "",
            title: nonEmpty(session.bookTitle) ?? nonEmpty(launch.bookTitle) ?? book?.title ?? "",
            author: nonEmpty(launch.bookAuthor) ?? book?.author ?? "",
            coverUrl: cover,
            host: ExtensionHostResolver.nonEmpty(session.bookHost) ?? ExtensionHostResolver.nonEmpty(launch.host)
                ?? ExtensionHostResolver.nonEmpty(book?.host),
            sourceName: nonEmpty(launch.bookSourceName) ?? nonEmpty(book?.sourceName)
        )
    }

    static func album(of model: VideoWatchModel) -> PlaylistAlbumInfo {
        PlaylistAlbumInfo(
            bookId: model.bookId,
            packageId: model.request.packageId,
            detailUrl: model.request.detailUrl,
            title: model.displayTitle,
            author: model.author,
            coverUrl: model.coverUrl,
            host: ExtensionHostResolver.nonEmpty(model.host) ?? ExtensionHostResolver.nonEmpty(model.request.host),
            sourceName: nonEmpty(model.request.sourceName)
        )
    }

    static func album(of book: Book) -> PlaylistAlbumInfo {
        PlaylistAlbumInfo(
            bookId: book.bookId,
            packageId: book.extensionPackageId,
            detailUrl: book.detailUrl,
            title: book.title,
            author: book.author,
            coverUrl: book.coverUrl,
            host: ExtensionHostResolver.nonEmpty(book.host),
            sourceName: nonEmpty(book.sourceName)
        )
    }

    /// Item danh sách chưa mở (không có `Book` trong tay). Id album = id mà trình nghe / màn xem sẽ dùng khi mở chính item
    /// này (`VideoWatchRequest.resolveBookId`, cùng quy tắc với `AudioListenRequest`): album / phim đã có trên máy thì
    /// `PlaylistAlbumItemsLoader` đọc đúng mục lục đã lưu ⇒ chỉ số mục khớp với lúc phát. `detailUrl` khác `item.link`
    /// khi mục Khám phá có action `detail` (link chi tiết = `input`).
    static func album(
        of item: ExtensionItemResult,
        detailUrl: String? = nil,
        packageId: String,
        sourceName: String,
        in context: ModelContext
    ) -> PlaylistAlbumInfo {
        let url = detailUrl ?? item.link
        let request = VideoWatchRequest(
            packageId: packageId,
            detailUrl: url,
            sourceName: sourceName,
            host: item.host,
            title: item.name,
            coverUrl: item.cover
        )
        return PlaylistAlbumInfo(
            bookId: request.resolveBookId(in: context),
            packageId: packageId,
            detailUrl: url,
            title: item.name,
            author: item.author,
            coverUrl: item.cover,
            host: ExtensionHostResolver.nonEmpty(item.host),
            sourceName: nonEmpty(sourceName)
        )
    }

    // MARK: - Mục

    /// Mục của một bài / tập thuộc `album`. `artist` chỉ dùng cho nhạc (rỗng ⇒ tác giả album).
    nonisolated static func item(
        kind: PlaylistKind,
        album: PlaylistAlbumInfo,
        index: Int,
        chapterUrl: String,
        title: String,
        artist: String = ""
    ) -> PlaylistItem {
        let subtitle: String
        switch kind {
        case .audio: subtitle = artist.isEmpty ? album.author : artist
        case .video: subtitle = album.title
        }
        return PlaylistItem(
            packageId: album.packageId,
            detailUrl: album.detailUrl,
            index: index,
            chapterUrl: chapterUrl,
            title: title,
            subtitle: subtitle,
            coverUrl: album.coverUrl,
            albumTitle: album.title,
            host: album.host,
            sourceName: album.sourceName
        )
    }

    // MARK: - Yêu cầu thêm

    /// Một bài của album đang mở trong trình nghe (hàng ở trang Danh sách).
    static func addRequest(track: AudioPlaybackSession.Track, in session: AudioPlaybackSession) -> PlaylistAddRequest? {
        guard let info = album(of: session) else { return nil }
        let entry = item(kind: .audio, album: info, index: track.index, chapterUrl: track.url, title: track.title, artist: track.artist)
        return PlaylistAddRequest(kind: .audio, item: entry)
    }

    /// Bài đang phát / đang nạp của trình nghe.
    static func addRequestForCurrentTrack(of session: AudioPlaybackSession) -> PlaylistAddRequest? {
        guard let index = session.currentTrackIndex, let track = session.track(at: index) else { return nil }
        return addRequest(track: track, in: session)
    }

    /// Tập đang phát của phiên phim.
    static func addRequestForCurrentEpisode(of session: VideoPlaybackSession) -> PlaylistAddRequest? {
        guard let episode = session.currentEpisode, !episode.isSection, let info = album(of: session) else { return nil }
        return addRequest(episode: episode, album: info)
    }

    static func addRequest(episode: VideoPlaybackSession.Episode, album: PlaylistAlbumInfo) -> PlaylistAddRequest {
        let entry = item(kind: .video, album: album, index: episode.index, chapterUrl: episode.url, title: episode.title)
        return PlaylistAddRequest(kind: .video, item: entry)
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
