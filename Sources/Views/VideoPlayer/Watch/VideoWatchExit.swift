import Foundation

/// Lối **rời màn xem** mà phần dưới khung phim (`VideoWatchDetailsView`) yêu cầu; `VideoPlayerScreen` thực hiện: thu nhỏ
/// (phim chạy nền ở hub) hoặc đóng, rồi **sau khi màn đã đóng** mới mở trang tiếp theo.
enum VideoWatchExit {
    /// Bấm nhãn thể loại ⇒ thu nhỏ, mở danh sách thể loại (trang phụ của `VideoWatchPresenter`).
    case genre(CategoryResult)
    /// "Mở trang chi tiết" của một đề xuất (hoặc đề xuất không phải phim) ⇒ thu nhỏ, mở `BookDetailView`.
    case openDetail(VideoWatchRequest)
    /// Nút Home ⇒ dừng / thu nhỏ theo 18+, tắt NSFW, sang tab Khám phá về trang gốc.
    case home
    /// Đổi nguồn xong (phim cũ sắp bị xoá) ⇒ đóng màn.
    case close
}
