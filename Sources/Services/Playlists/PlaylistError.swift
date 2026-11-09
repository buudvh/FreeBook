import Foundation

/// Lỗi của phân hệ playlist — chữ hiện thẳng lên toast nên viết cho người dùng đọc.
enum PlaylistError: LocalizedError, Equatable {
    case emptyName
    case notFound
    case saveFailed(String)
    /// Album / phim không có tiện ích chạy được và chưa có mục lục trên máy.
    case sourceUnavailable
    /// Mục lục không có bài / tập nào phát được.
    case emptyAlbum

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Tên playlist không được để trống."
        case .notFound:
            return "Không tìm thấy playlist (có thể đã bị xoá)."
        case .saveFailed(let message):
            return "Không lưu được playlist: \(message)"
        case .sourceUnavailable:
            return "Tiện ích nguồn chưa được cài hoặc đã bị gỡ."
        case .emptyAlbum:
            return "Không có bài / tập nào để thêm."
        }
    }
}
