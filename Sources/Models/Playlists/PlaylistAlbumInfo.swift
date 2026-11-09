import Foundation

/// Thông tin album / phim chứa các mục sắp vào playlist — chép một lần từ chỗ đang mở (phiên nghe, phiên xem, màn xem,
/// `Book` trên Kệ) để dựng `PlaylistItem` và để `PlaylistAlbumItemsLoader` đọc mục lục.
///
/// Bản sao bất biến (`Sendable`) — đi qua được ranh giới isolation khi tải mục lục ở nền.
struct PlaylistAlbumInfo: Sendable, Equatable {
    /// Id `Book` trên máy (đọc mục lục đã lưu); rỗng khi chưa có `Book`.
    let bookId: String
    let packageId: String
    /// Link chi tiết nguyên văn.
    let detailUrl: String
    let title: String
    /// Tác giả / nghệ sĩ của album; dòng phụ của bài nhạc khi bài không có nghệ sĩ riêng.
    let author: String
    let coverUrl: String
    let host: String?
    let sourceName: String?
}
