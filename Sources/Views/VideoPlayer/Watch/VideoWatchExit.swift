import Foundation

/// Lối **rời màn xem** mà phần dưới khung phim (`VideoWatchDetailsView`) yêu cầu; `VideoPlayerScreen` thực hiện: thu nhỏ
/// (phim chạy nền ở hub / cửa sổ nhỏ) hoặc đóng, rồi **sau khi màn đã đóng** mới làm việc tiếp theo. Chi tiết của đề xuất
/// không phải phim không rời màn: nó mở trang toàn màn đè lên màn xem (`VideoWatchPagePresenter.openDetail`).
enum VideoWatchExit {
    /// Nút Home ⇒ dừng / thu nhỏ theo 18+, tắt NSFW, sang tab Khám phá về trang gốc.
    case home
    /// Đổi nguồn xong (phim cũ sắp bị xoá) ⇒ đóng màn.
    case close
    /// Thể loại (nhãn trên tên, chip của sheet Thông tin) hoặc "Xem thêm ›" của một nhóm đề xuất. Màn đang phát phim của nó
    /// (không nhúng trang) ⇒ phim vào cửa sổ nhỏ, màn đóng rồi mới mở trang danh sách; còn lại (màn hiện bìa vì phim khác
    /// chạy nền, phim nhúng trang) ⇒ trang đè lên màn như cũ.
    case openCategory(CategoryResult)
}
