import SwiftUI

/// Phong cách hiển thị của một row truyện. Cover và title đồng bộ ở mọi style;
/// chỉ khác phần thông tin phụ bên dưới title.
enum BookListItemStyle {
    /// Kệ sách / Lịch sử đọc / sheet chọn truyện: author (Hán-Việt) + pill nguồn + dòng "Đang đọc".
    case shelfOrHistory
    /// Discovery / genre: hiển thị description thay cho author/source.
    case discovery
}
