import UIKit

/// Chữ + ảnh của bài đang nghe trên màn khoá / Trung tâm điều khiển:
/// - Nguồn thường: tiêu đề = tên bài; dòng phụ (Artist) = nghệ sĩ của bài (`description` của mục `toc`), thiếu ⇒ tác giả
///   album, thiếu nữa ⇒ không ghi; Album = tên album; ảnh = bìa album (cắt vuông).
/// - Nguồn 18+ (`RepositoryFilterPolicy.isNsfwBook`, cùng luật với phim): **một** dòng "Đang phát", không dòng phụ, không
///   tên album, ảnh = icon app (`LockScreenAppIcon`) — không đọc, không tải bìa.
struct AudioNowPlayingMetadata {
    let title: String
    /// `nil` ⇒ không ghi dòng phụ.
    let artist: String?
    /// `nil` ⇒ không ghi Album.
    let albumTitle: String?
    let artwork: UIImage?

    static func make(
        isNsfw: Bool,
        trackTitle: String,
        artist: String,
        albumAuthor: String,
        albumTitle: String,
        cover: UIImage?
    ) -> AudioNowPlayingMetadata {
        guard !isNsfw else {
            return AudioNowPlayingMetadata(
                title: VideoNowPlayingMetadata.nsfwTitle,
                artist: nil,
                albumTitle: nil,
                artwork: UIImage(named: VideoNowPlayingMetadata.appIconAssetName)
            )
        }
        let trimmedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAuthor = albumAuthor.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAlbum = albumTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let subtitle = trimmedArtist.isEmpty ? trimmedAuthor : trimmedArtist
        // Tên bài chưa có (đang nạp lượt đầu) ⇒ tạm dùng tên album.
        let title = trackTitle.isEmpty ? trimmedAlbum : trackTitle
        return AudioNowPlayingMetadata(
            title: title,
            artist: subtitle.isEmpty ? nil : subtitle,
            albumTitle: trimmedAlbum.isEmpty || trimmedAlbum == title ? nil : trimmedAlbum,
            artwork: cover
        )
    }
}
