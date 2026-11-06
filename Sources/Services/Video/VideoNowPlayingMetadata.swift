import UIKit

/// Chữ + ảnh của phim trên màn khoá / Trung tâm điều khiển (1.3.764, anh Bửu chốt qua mockup):
/// - Phim thường: tiêu đề = tên phim; dòng phụ = "Tác giả · Tập N" — tên tập chỉ khi phim có từ 2 tập phát được, thiếu
///   tác giả thì chỉ còn tên tập (phim một tập không tác giả ⇒ không dòng phụ); ảnh = bìa phim
///   (`VideoPlaybackSession+NowPlaying` nạp).
/// - Phim 18+ (`RepositoryFilterPolicy.isNsfwBook`, cùng luật với tắt tiếng / thu nhỏ): **một** dòng "Đang phát", không dòng
///   phụ, không tên tập (tên tập của nguồn 18+ hay chính là tên phim), ảnh = icon app (`LockScreenAppIcon` trong Assets) —
///   không đọc, không tải bìa.
struct VideoNowPlayingMetadata {
    static let nsfwTitle = "Đang phát"
    static let appIconAssetName = "LockScreenAppIcon"

    let title: String
    /// `nil` ⇒ không ghi dòng phụ.
    let subtitle: String?
    let artwork: UIImage?

    static func make(
        isNsfw: Bool,
        bookTitle: String,
        author: String,
        episodeLabel: String,
        showsEpisode: Bool,
        cover: UIImage?
    ) -> VideoNowPlayingMetadata {
        guard !isNsfw else {
            return VideoNowPlayingMetadata(title: nsfwTitle, subtitle: nil, artwork: UIImage(named: appIconAssetName))
        }
        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
        let episode = showsEpisode ? episodeLabel : ""
        let parts = [trimmedAuthor, episode].filter { !$0.isEmpty }
        // Tên phim chưa có (đang nạp lượt đầu) ⇒ tạm dùng tên tập như trước.
        let title = bookTitle.isEmpty ? episodeLabel : bookTitle
        return VideoNowPlayingMetadata(
            title: title,
            subtitle: parts.isEmpty ? nil : parts.joined(separator: " · "),
            artwork: cover
        )
    }
}
