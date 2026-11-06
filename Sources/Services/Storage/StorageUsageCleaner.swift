import Foundation

/// Xoá bốn loại dữ liệu "an toàn" của màn Dung lượng — dùng lại đúng đường xoá đang có của từng owner, không tự xoá
/// thư mục của người khác:
/// - Cache ảnh truyện tranh ⇒ `ComicImageLoader.clearDiskCache()` (chính instance cache của loader).
/// - File xuất ⇒ `DownloadManager.clearFinishedExportTasks()` (chỉ tác vụ xuất đã xong/lỗi/huỷ + file của chúng; mục mồ
///   côi chỉ dọn khi không còn tác vụ xuất nào chạy).
/// - Nhật ký ⇒ `AppLogger.shared.clear()`.
/// - Báo cáo kiểm tra ⇒ `CheckReportRepository.deleteAll` (chừa lượt đang chạy; trang Báo cáo kiểm tra đọc lại luôn).
///
/// Không báo toast (Services không gọi `ToastManager`); màn gọi đo lại rồi tự báo.
public enum StorageUsageCleaner {
    @MainActor
    public static func clear(_ category: StorageUsageCategory) async {
        switch category {
        case .comicImageCache:
            await ComicImageLoader.shared.clearDiskCache()
        case .exports:
            await DownloadManager.shared.clearFinishedExportTasks()
        case .logs:
            AppLogger.shared.clear()
        case .checkReports:
            await CheckReportRepository.shared.deleteAll(CheckReportKind.allCases)
        default:
            return
        }
        AppLogger.shared.log("🧹 [StorageUsage] Đã xoá: \(category.title)")
    }
}
