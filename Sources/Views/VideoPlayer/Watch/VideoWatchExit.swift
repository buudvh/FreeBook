import Foundation

/// Lối **rời màn xem** mà phần dưới khung phim (`VideoWatchDetailsView`) yêu cầu; `VideoPlayerScreen` thực hiện: thu nhỏ
/// (phim chạy nền ở hub) hoặc đóng, rồi **sau khi màn đã đóng** mới làm việc tiếp theo. Thể loại, "Xem thêm" và Chi tiết
/// của đề xuất không rời màn nữa (1.3.744): chúng mở trang toàn màn đè lên màn xem (`VideoWatchPagePresenter`).
enum VideoWatchExit {
    /// Nút Home ⇒ dừng / thu nhỏ theo 18+, tắt NSFW, sang tab Khám phá về trang gốc.
    case home
    /// Đổi nguồn xong (phim cũ sắp bị xoá) ⇒ đóng màn.
    case close
}
