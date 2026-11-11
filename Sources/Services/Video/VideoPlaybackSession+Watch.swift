import Foundation

/// Phần của phiên phát dành cho màn xem phim (`VideoWatchModel`). Không đổi luồng phát: phiên vẫn đọc mục lục **một lần**
/// lúc mở (`+Loading`), hàm ở đây chỉ nhận danh sách tập màn xem vừa làm mới.
extension VideoPlaybackSession {
    /// Màn xem vừa làm mới mục lục của phim **đang mở** và đã ghi xong vào `ChapterStore` ⇒ cập nhật danh sách tập mà
    /// không nạp lại tập đang xem. Chỉ nhận khi nguồn **thêm tập ở cuối** (link hiện có là phần đầu của bản mới): đổi thứ
    /// tự / bớt tập thì `currentEpisodeIndex`, tập kế và tên tập lưu tiến độ sẽ trỏ sang tập khác. Tên hiển thị (phồn →
    /// giản / dịch) gắn lại ngay theo bảng tên đã tính rồi tính thêm cho tập mới (`refreshDisplayNames`).
    func adoptRefreshedEpisodes(_ refreshed: [Episode], bookId: String) {
        let currentURLs = episodes.map(\.url)
        let refreshedURLs = refreshed.map(\.url)
        guard launch?.bookId == bookId, refreshedURLs != currentURLs, refreshedURLs.starts(with: currentURLs) else { return }
        let oldCount = episodes.count
        episodes = refreshed
        refreshDisplayNames()
        AppLogger.shared.log("🎬 [VideoPlayer] Nhận mục lục làm mới từ màn xem: \(oldCount) → \(episodes.count) tập")
    }
}
