import Foundation

/// Lỗi của tầng xuất truyện. Tầng Services **không** gọi `ToastManager` — thông báo tiếng Việt đi kèm
/// lỗi rồi được `DownloadManager` đổ vào `errorMessage` của tác vụ và event toast.
enum ExportRenderError: LocalizedError {
    case cannotCreateFile(String)
    case emptyExport
    case archiveTooLarge
    case sizeLimitExceeded(String)

    var errorDescription: String? {
        switch self {
        case .cannotCreateFile(let path):
            return "Không tạo được tệp xuất tạm tại \(path)"
        case .emptyExport:
            return "Bản xuất không có nội dung nào để ghi."
        case .archiveTooLarge:
            return "Bản xuất vượt giới hạn 4 GB của định dạng ZIP."
        case .sizeLimitExceeded(let detail):
            return detail
        }
    }
}
